import Foundation

/// An explicit request to the charge-policy agent; holding never requests a deliberate discharge.
public enum BatteryChargeIntent: Equatable, Sendable {
    case charge(to: Int)
    case hold
    case discharge(to: Int)
}

/// A configuration write, a registered firmware target, and stopped charging are separate facts.
public struct BatteryChargeApplicationStatus: Codable, Equatable, Sendable {
    public let requestedLimit: Int
    public let registeredLimit: Int?
    public let elapsed: TimeInterval
    public let releasePending: Bool
    public var registered: Bool { !releasePending && registeredLimit == requestedLimit }
    public init(requestedLimit: Int, registeredLimit: Int?, elapsed: TimeInterval, releasePending: Bool = false) {
        self.requestedLimit = requestedLimit; self.registeredLimit = registeredLimit; self.elapsed = elapsed
        self.releasePending = releasePending
    }
}

/// Owns only the two manual-charge-policy preferences, after a durable snapshot has been saved.
/// All calls are confined to the helper battery queue; no delayed mutation survives restoration.
public final class NativeChargePolicyHardware: ChargeHardware {
    public static let registrationGrace: TimeInterval = 150
    private let driver: any NativeChargePolicyDriver
    private let identity: () -> String?
    private let onAC: () -> Bool?
    private var captured: NativeChargePolicyPreferences?
    private var requested: (limit: Int, since: TimeInterval)?
    private var lastIntent: BatteryChargeIntent?
    private var verificationSince: TimeInterval?
    private var unconfirmedTargets = Set<Int>()
    private var resumeReleaseStarted: TimeInterval?
    private var restoringCleared = false
    private var restoredPreferences = false
    private var lastOnAC: Bool?

    public convenience init() {
        self.init(driver: SystemNativeChargePolicyDriver(), identity: { BatteryMachine.identity }, onAC: {
            let snapshot = BatterySnapshot.read()
            return snapshot.powerStateKnown ? snapshot.onAC : nil
        })
    }
    public init(driver: any NativeChargePolicyDriver, identity: @escaping () -> String?, onAC: @escaping () -> Bool?) {
        self.driver = driver; self.identity = identity; self.onAC = onAC
    }
    public var capabilities: BatteryControlCapabilities {
        let available = driver.isAvailable && (try? checkedPreferences()) != nil && driver.calibrationOverride() != nil
        return .init(backend: .nativePolicy, supportedLimits: available ? Array(50...100) : [], supportsThermalProtection: true)
    }
    private func checkedPreferences() throws -> NativeChargePolicyPreferences {
        guard driver.isAvailable else { throw BatteryNativePolicyError.unavailable }
        let value = try driver.readPreferences()
        guard value.isValid else { throw BatteryNativePolicyError.invalidState }
        return value
    }
    private func requireNoCalibration() throws {
        guard driver.calibrationOverride() == false else { throw NativeChargeError(code: -8) }
    }
    public func captureRecovery() throws -> BatteryRecoveryRecord {
        guard let machineID = identity() else { throw BatteryNativePolicyError.invalidState }
        let original = try checkedPreferences()
        try requireNoCalibration()
        let registered = try driver.registeredLimit()
        let originalTarget: Int?
        if original.featureEnabled == true, case .integer(let limit) = original.limit { originalTarget = limit }
        else { originalTarget = nil }
        guard registered == originalTarget || (registered == nil && originalTarget != nil && onAC() == false) else {
            throw BatteryNativePolicyError.configurationSettling
        }
        captured = original; requested = nil; lastIntent = nil; verificationSince = nil
        unconfirmedTargets.removeAll(); resumeReleaseStarted = nil
        restoringCleared = false; restoredPreferences = false; lastOnAC = nil
        return .init(backend: .nativePolicy, machineID: machineID, nativePolicyPreferences: original)
    }
    public func prepareForControl() throws {
        guard captured != nil else { throw BatteryNativePolicyError.invalidState }
    }
    public func readSwitch() throws -> UInt8 {
        let original = try checkedPreferences()
        switch original.featureState {
        case .absent: return 0
        case .integer(let value): return value == 1 ? 2 : 0
        case .boolean(let value): return value ? 2 : 0
        }
    }
    public func writeSwitch(_ value: UInt8) throws { throw BatteryNativePolicyError.invalidState }
    public func setChargeLimit(_ limit: Int?) throws { throw BatteryNativePolicyError.invalidState }
    public func validateDischarge() throws { try requireNoCalibration() }

    public func applyChargeIntent(_ intent: BatteryChargeIntent, snapshot: BatterySnapshot, now: TimeInterval) throws {
        guard captured != nil, now.isFinite, now >= 0, snapshot.reliableForControl, let percent = snapshot.percent else {
            throw BatteryNativePolicyError.invalidState
        }
        try requireNoCalibration()
        if lastOnAC == false, snapshot.onAC, let previous = requested {
            requested = (previous.limit, now)
            verificationSince = now
            if resumeReleaseStarted != nil { resumeReleaseStarted = now }
        }
        lastOnAC = snapshot.onAC
        let target: Int
        let wasHolding = lastIntent == .hold
        let wasDischarging: Bool
        if case .discharge = lastIntent { wasDischarging = true } else { wasDischarging = false }
        var releaseBeforeRequest = false
        switch intent {
        case .charge(let upper):
            guard (50...100).contains(upper) else { throw BatteryNativePolicyError.invalidState }
            // On battery, a ceiling below today's level would arm an unwanted discharge at reconnect.
            target = snapshot.onAC ? upper : max(upper, percent)
            releaseBeforeRequest = wasHolding || wasDischarging
        case .hold:
            // Track natural declines too: a fixed ceiling would let firmware refill at its own lower threshold.
            // The request never asks for a ceiling below the just-observed battery level.
            target = percent
            releaseBeforeRequest = wasDischarging
        case .discharge(let lower):
            guard snapshot.onAC, (10...100).contains(lower) else { throw BatteryNativePolicyError.powerRequired }
            target = lower
        }
        guard (1...100).contains(target) else { throw BatteryNativePolicyError.invalidState }
        if lastIntent != intent {
            verificationSince = now; unconfirmedTargets.removeAll()
        }
        let expected = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(target))
        let current = try checkedPreferences()
        var releaseConsumed = false
        if releaseBeforeRequest, resumeReleaseStarted == nil {
            restoringCleared = false; restoredPreferences = false
            try driver.clearRegisteredLimit()
            resumeReleaseStarted = now
        }
        if let started = resumeReleaseStarted {
            requested = (target, started); lastIntent = intent
            if try driver.registeredLimit() != nil {
                if snapshot.onAC && now - started >= Self.registrationGrace { throw BatteryNativePolicyError.registrationFailed }
                return
            }
            // The release has been consumed by powerd. Only now may a new preference request be posted.
            resumeReleaseStarted = nil; verificationSince = now
            releaseConsumed = true
        }
        if requested?.limit != target || current != expected || releaseBeforeRequest || releaseConsumed {
            // Reconcile only this owned policy, never fall back to SMC or adapter isolation.
            restoringCleared = false; restoredPreferences = false
            try driver.apply(limit: target)
            requested = (target, now)
            unconfirmedTargets.insert(target)
        }
        lastIntent = intent
        if let application = try chargeApplicationStatus(now: now) {
            let firstConfirmation = application.registeredLimit.map { unconfirmedTargets.remove($0) != nil } ?? false
            if application.registered || firstConfirmation {
                verificationSince = now
            }
            if snapshot.onAC, !application.registered, now - (verificationSince ?? now) >= Self.registrationGrace {
                throw BatteryNativePolicyError.registrationFailed
            }
        }
    }
    public func chargeApplicationStatus(now: TimeInterval) throws -> BatteryChargeApplicationStatus? {
        guard let requested else { return nil }
        guard now.isFinite, now >= requested.since else { throw BatteryNativePolicyError.invalidState }
        return .init(requestedLimit: requested.limit, registeredLimit: try driver.registeredLimit(),
                     elapsed: now - requested.since, releasePending: resumeReleaseStarted != nil)
    }
    public func restore(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid, record.backend == .nativePolicy, record.machineID == identity(),
              let original = record.nativePolicyPreferences else { throw BatteryNativePolicyError.invalidState }
        // Clearing via the agent is required: simply setting FeatureState=0 leaves a registered target behind.
        if !restoringCleared {
            try driver.clearRegisteredLimit()
            restoringCleared = true
        }
        // Do not put back an enabled original until our own registration has actually gone away.
        if !restoredPreferences {
            guard try driver.registeredLimit() == nil else { throw BatteryNativePolicyError.restorationPending }
            try driver.restorePreferences(original)
            restoredPreferences = true
        }
        guard try driver.readPreferences() == original else {
            restoredPreferences = false; restoringCleared = false
            throw BatteryNativePolicyError.invalidState
        }
        let registered = try driver.registeredLimit()
        let expected: Int?
        switch original.featureState {
        case .integer(1), .boolean(true):
            guard case .integer(let limit) = original.limit else { throw BatteryNativePolicyError.invalidState }
            expected = limit
        default: expected = nil
        }
        if registered != expected {
            // An unplugged Mac may defer an original enabled target until its next AC session.
            guard onAC() == false, registered == nil else { throw BatteryNativePolicyError.restorationPending }
        }
        // A sleep restoration retains ownership, but its next heartbeat starts a fresh request and grace period.
        requested = nil; lastIntent = nil; lastOnAC = nil; verificationSince = nil
        unconfirmedTargets.removeAll(); resumeReleaseStarted = nil
    }
    public func endSession() {
        captured = nil; requested = nil; lastIntent = nil; verificationSince = nil
        unconfirmedTargets.removeAll(); resumeReleaseStarted = nil
        restoringCleared = false; restoredPreferences = false; lastOnAC = nil
    }
}

/// A failed request keeps the durable snapshot until restoration has been verified.
public enum BatteryNativePolicyError: LocalizedError {
    case unavailable, invalidState, powerRequired, registrationFailed, restorationPending, configurationSettling
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "La méthode de politique de charge Apple est indisponible sur ce Mac."
        case .invalidState: return "La politique de charge est inconnue ou sa restauration n’est pas confirmée."
        case .powerRequired: return "Branchez le Mac pour lancer la décharge contrôlée."
        case .registrationFailed: return "macOS n’a pas enregistré la limite dans le délai prévu. La configuration initiale est restaurée."
        case .restorationPending: return "Restauration de la limite initiale en cours d’application par macOS."
        case .configurationSettling: return "Les réglages de charge existants ne sont pas encore cohérents avec macOS. Fermez les autres contrôleurs et attendez leur restauration avant d’activer MacCare."
        }
    }
}
