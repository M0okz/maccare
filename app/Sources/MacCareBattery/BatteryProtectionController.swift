import Foundation

/// Confined to the helper battery queue. An interrupted/disabled session can only restore;
/// neither polling nor a late heartbeat can re-enable its charge policy.
public final class BatteryProtectionController {
    public static let leaseDuration: TimeInterval = 90
    public static let wakeGrace: TimeInterval = 15
    private let hardware: any ChargeHardware
    private let markRecovery: (BatteryRecoveryRecord) throws -> Void
    private let clearRecovery: () throws -> Void
    private var recovery: BatteryRecoveryRecord?
    private var sessionCapabilities: BatteryControlCapabilities?
    private var owner: UInt32?
    private var sessionID: UUID?
    private var deadline: TimeInterval = 0
    private var configuration: BatteryConfiguration?
    private var policy = BatteryProtectionPolicy()
    private var suspended = false
    private var topUp = false
    private var sleeping = false
    private var awaitingHeartbeat = false
    private var restoring = false
    private var failure: String?
    private var message = "Protection désactivée"
    public var requiresWatchdog: Bool { recovery != nil }

    public init(hardware: any ChargeHardware, markRecovery: @escaping (BatteryRecoveryRecord) throws -> Void,
                clearRecovery: @escaping () throws -> Void) {
        self.hardware = hardware; self.markRecovery = markRecovery; self.clearRecovery = clearRecovery
    }
    public func recover(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid else { throw BatteryHardwareError(code: -3) }
        recovery = record; sessionCapabilities = .init(backend: record.backend); restoring = true
        try finishRestoration()
    }
    public func execute(_ command: BatteryCommand, configuration newConfiguration: BatteryConfiguration?,
                        uid: UInt32, sessionID callerSession: UUID? = nil,
                        snapshot: BatterySnapshot, now: TimeInterval) -> BatteryProtectionStatus {
        // A read-only call never runs the policy, renews a lease or writes hardware.
        if command == .status { return status(snapshot, now: now, uid: uid, session: callerSession) }
        do {
            guard uid >= 501, let callerSession else { throw ControlError("Session de contrôle invalide.") }
            if let owner {
                // A new instance of the same local user may explicitly stop an orphan session,
                // but cannot renew or reconfigure it without its unpredictable session ID.
                guard owner == uid, command == .disable || sessionID == callerSession else {
                    throw ControlError("La protection est gérée par une autre session de MacCare.")
                }
            }
            guard !restoring || command == .disable else {
                throw ControlError("Restauration de la charge en cours. Aucune protection ne sera relancée avant sa réussite.")
            }
            switch command {
            case .status: break
            case .disable:
                if recovery != nil { try stop() }
            case .enable:
                guard !sleeping else { throw ControlError("Attendez la sortie de veille avant d’activer la protection.") }
                guard snapshot.reliableForControl else { throw ControlError("Les mesures de batterie sont insuffisantes pour piloter la charge.") }
                guard let newConfiguration, newConfiguration.isValid else { throw ControlError("Réglages de protection invalides.") }
                let capabilities = sessionCapabilities ?? hardware.capabilities
                guard capabilities.isValid, capabilities.supportedLimits.contains(newConfiguration.limit) else {
                    throw ControlError("Cette limite de charge n’est pas disponible avec la méthode de contrôle actuelle.")
                }
                if newConfiguration.sailingWidth != nil && !capabilities.supportsSailing {
                    throw ControlError("La plage de maintien personnalisée nécessite un contrôle matériel compatible.")
                }
                if !capabilities.supportsThermalProtection && newConfiguration.thermalProtection {
                    throw ControlError("Cette méthode permet une limite de charge, mais pas la pause thermique personnalisée.")
                }
                if newConfiguration.thermalProtection && !snapshot.reliableTemperature {
                    throw ControlError("La température est indisponible. Désactivez la pause thermique pour utiliser uniquement la limite de charge.")
                }
                if recovery == nil {
                    let record = try hardware.captureRecovery()
                    guard record.isValid, record.backend == capabilities.backend else {
                        hardware.endSession()
                        throw ControlError("La méthode de contrôle a changé. Actualisez son état avant de réessayer.")
                    }
                    do { try markRecovery(record) } catch { hardware.endSession(); throw error }
                    recovery = record; sessionCapabilities = capabilities; owner = uid; sessionID = callerSession
                    // The durable restoration record precedes every mutation. Native limit
                    // backends prepare without clearing or replacing the existing limit.
                    try hardware.prepareForControl()
                } else if now >= deadline {
                    try stop()
                    throw ControlError("La session précédente a expiré. Réactivez la protection pour continuer.")
                }
                configuration = newConfiguration; policy = .init(); topUp = false; failure = nil
                awaitingHeartbeat = false; deadline = now + Self.leaseDuration
                try update(snapshot, now: now)
            case .heartbeat, .topUp, .cancelTopUp:
                guard owner == uid, sessionID == callerSession, now < deadline else {
                    if recovery != nil { try stop() }
                    throw ControlError("La protection a expiré. Réactivez-la pour continuer.")
                }
                if command == .topUp && !snapshot.onAC { throw ControlError("Branchez le Mac pour lancer une recharge ponctuelle.") }
                if command == .topUp { topUp = true }
                if command == .cancelTopUp { topUp = false }
                deadline = now + Self.leaseDuration
                if !sleeping { awaitingHeartbeat = false }
                try update(snapshot, now: now)
            }
        } catch {
            let issue = error.localizedDescription
            if !(error is ControlError), recovery != nil {
                restoring = true; topUp = false
                do { try finishRestoration() } catch { /* watchdog retries, never resumes policy */ }
            }
            failure = issue
            message = restoring ? "Restauration de la charge en cours" : "Protection à vérifier"
        }
        return status(snapshot, now: now, uid: uid, session: callerSession)
    }
    public func tick(snapshot: BatterySnapshot, now: TimeInterval) -> BatteryProtectionStatus {
        do {
            if restoring { try finishRestoration() }
            else { try update(snapshot, now: now) }
        } catch {
            let issue = error.localizedDescription
            restoring = recovery != nil; topUp = false
            do { try finishRestoration() } catch { /* next tick retries the exact original state */ }
            failure = issue
            message = restoring ? "Restauration de la charge en cours" : "Protection interrompue"
        }
        return status(snapshot, now: now, uid: nil, session: nil)
    }
    public func prepareForSleep() throws {
        sleeping = true; topUp = false; awaitingHeartbeat = true
        guard let recovery else { return }
        do { try hardware.restore(recovery); suspended = false }
        catch { restoring = true; failure = error.localizedDescription; throw error }
        message = "En veille · charge rendue à macOS"
    }
    public func didWake(now: TimeInterval) {
        sleeping = false
        if recovery != nil && !restoring {
            awaitingHeartbeat = true; deadline = now + Self.wakeGrace
            message = "Charge gérée par macOS · attente de MacCare après la veille"
        }
    }
    public func shutdown() throws { if recovery != nil { try stop() } }

    private func update(_ snapshot: BatterySnapshot, now: TimeInterval) throws {
        guard recovery != nil else { return }
        if restoring { try finishRestoration(); return }
        if now >= deadline {
            try stop(); message = "Protection arrêtée · MacCare ne répond plus"; return
        }
        if sleeping || awaitingHeartbeat { return }
        guard snapshot.reliableForControl, let configuration else {
            try stop(); message = "Protection arrêtée · mesures indisponibles"; return
        }
        if topUp && (!snapshot.onAC || snapshot.percent == 100) { topUp = false }
        if sessionCapabilities?.managesChargeLimit == true {
            if !topUp, configuration.sailingWidth != nil, sessionCapabilities?.backend == .firmware {
                try hardware.setChargeBand(upper: configuration.limit, lower: configuration.resumeLimit)
            } else { try hardware.setChargeLimit(topUp ? nil : configuration.limit) }
            suspended = !topUp && snapshot.onAC && (snapshot.percent ?? 0) >= configuration.limit && !snapshot.charging
            if recovery?.backend == .nativeLimit {
                message = topUp ? "Recharge ponctuelle à 100 % · limite native suspendue"
                    : "Limite native de macOS : \(configuration.limit) %"
            } else {
                message = topUp ? "Recharge ponctuelle à 100 % · limite matérielle suspendue"
                    : "Limite matérielle de \(configuration.limit) % · pause thermique indisponible"
            }
        } else {
            let decision = policy.evaluate(snapshot, configuration: configuration, topUp: topUp)
            let value: UInt8 = decision.suspend ? 2 : 0
            if try hardware.readSwitch() != value { try hardware.writeSwitch(value) }
            suspended = decision.suspend; message = decision.reason
        }
        failure = nil
    }
    private func stop() throws {
        restoring = true; topUp = false
        try finishRestoration()
    }
    private func finishRestoration() throws {
        guard let recovery else { restoring = false; return }
        try hardware.restore(recovery)
        suspended = false
        try clearRecovery()
        self.recovery = nil; sessionCapabilities = nil; hardware.endSession()
        owner = nil; sessionID = nil; configuration = nil; topUp = false
        policy = .init(); restoring = false; awaitingHeartbeat = false
        message = "Protection désactivée"
    }
    private func status(_ snapshot: BatterySnapshot, now: TimeInterval, uid: UInt32?, session: UUID?) -> BatteryProtectionStatus {
        var hardwareError: String?
        var capabilities = sessionCapabilities
        let supported: Bool
        if snapshot.present && snapshot.appleSilicon {
            do {
                _ = try hardware.readSwitch()
                let observed = sessionCapabilities ?? hardware.capabilities
                guard observed.isValid else { throw BatteryHardwareError(code: -1) }
                capabilities = observed; supported = true
            }
            catch { supported = false; hardwareError = error.localizedDescription }
        } else { supported = false }
        let expired = recovery != nil && now >= deadline && !sleeping
        return .init(snapshot: snapshot, firmwareManaged: recovery?.backend == .firmware || (recovery == nil && hardware.firmwareManaged),
                     supported: supported, active: owner != nil && !restoring && !expired,
                     suspended: suspended, topUp: topUp, configuration: configuration,
                     message: expired ? "Protection expirée · restauration en attente" : message,
                     error: failure ?? (supported ? nil : hardwareError), restoring: restoring || expired,
                     ownedByCaller: owner != nil && owner == uid && sessionID == session, capabilities: capabilities)
    }
    private struct ControlError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
