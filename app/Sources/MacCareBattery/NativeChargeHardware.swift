import Foundation
import CMacCarePowerUI

/// A read of Apple's configured limit, separate from whether the battery is charging.
public struct NativeChargeReading: Equatable, Sendable {
    public var state: NativeChargeState
    public var supportedLimits: [Int]
    public var calibrationOverride: Bool?
    public init(state: NativeChargeState, supportedLimits: [Int], calibrationOverride: Bool? = false) {
        self.state = state; self.supportedLimits = supportedLimits; self.calibrationOverride = calibrationOverride
    }
    var isValid: Bool {
        state.isValid && !supportedLimits.isEmpty && supportedLimits.count <= 21 &&
        Set(supportedLimits).count == supportedLimits.count && supportedLimits == supportedLimits.sorted() &&
        supportedLimits.allSatisfy { (80...100).contains($0) } && supportedLimits.contains(state.limit) && supportedLimits.contains(100)
    }
    var canRestore: Bool { isValid && state.enabled == (state.limit < 100) }
}

public protocol NativeChargeDriver {
    func read() throws -> NativeChargeReading
    func setLimit(_ limit: Int) throws
    func restore(_ state: NativeChargeState) throws
}

/// Calls are confined to the helper's serial battery queue. No detached timeout can
/// leave a mutation running after restoration has started.
public struct SystemNativeChargeDriver: NativeChargeDriver {
    public init() {}
    public func read() throws -> NativeChargeReading {
        var state = MacCarePowerUIState()
        var values = [Int32](repeating: 0, count: 21)
        var count = 0
        let result = values.withUnsafeMutableBufferPointer {
            maccare_powerui_read(&state, $0.baseAddress, $0.count, &count)
        }
        guard result == 0 else { throw NativeChargeError(code: result) }
        guard count > 0, count <= values.count, state.enabled == 0 || state.enabled == 1 else { throw NativeChargeError(code: -3) }
        let reading = NativeChargeReading(state: .init(enabled: state.enabled == 1, limit: Int(state.limit)),
            supportedLimits: values.prefix(count).map(Int.init),
            calibrationOverride: state.calibration_override < 0 ? nil : state.calibration_override != 0)
        guard reading.isValid else { throw NativeChargeError(code: -3) }
        return reading
    }
    public func setLimit(_ limit: Int) throws {
        guard (80...100).contains(limit) else { throw NativeChargeError(code: -4) }
        let result = maccare_powerui_set_limit(Int32(limit))
        guard result == 0 else { throw NativeChargeError(code: result) }
    }
    public func restore(_ state: NativeChargeState) throws {
        guard state.isValid else { throw NativeChargeError(code: -3) }
        let result = maccare_powerui_restore(state.enabled ? 1 : 0, Int32(state.limit))
        guard result == 0 else { throw NativeChargeError(code: result) }
    }
}

public struct NativeChargeError: LocalizedError {
    public let code: Int32
    public var errorDescription: String? {
        switch code {
        case -8: return "macOS effectue ou prépare un étalonnage de la batterie. Le contrôle attend la fin de cette opération."
        case -4: return "Cette limite de charge n’est pas proposée par macOS sur ce Mac."
        case -2, -3: return "La méthode native de charge a changé ou son état est inconnu. Aucun autre mécanisme ne sera essayé pendant la restauration."
        default: return "La limite native de macOS est indisponible ou n’a pas confirmé le réglage (code \(code))."
        }
    }
}

/// Owns only the native charge limit. Optimized charging and unrelated preferences
/// are never changed. The exact original limit is durable before the first write.
public final class NativeChargeHardware: ChargeHardware {
    private let driver: any NativeChargeDriver
    private let identity: () -> String?
    private var pinned: BatteryControlCapabilities?
    public convenience init() { self.init(driver: SystemNativeChargeDriver(), identity: { BatteryMachine.identity }) }
    public init(driver: any NativeChargeDriver, identity: @escaping () -> String?) {
        self.driver = driver; self.identity = identity
    }
    public var capabilities: BatteryControlCapabilities {
        if let pinned { return pinned }
        return .init(backend: .nativeLimit, supportedLimits: (try? checkedReading().supportedLimits) ?? [], supportsThermalProtection: false)
    }
    private func checkedReading() throws -> NativeChargeReading {
        let reading = try driver.read()
        guard reading.isValid else { throw NativeChargeError(code: -3) }
        return reading
    }
    public func captureRecovery() throws -> BatteryRecoveryRecord {
        guard let machineID = identity() else { throw BatteryHardwareError(code: -3) }
        let reading = try checkedReading()
        guard reading.canRestore else { throw NativeChargeError(code: -3) }
        guard reading.calibrationOverride == false else { throw NativeChargeError(code: -8) }
        pinned = .init(backend: .nativeLimit, supportedLimits: reading.supportedLimits, supportsThermalProtection: false)
        return .init(backend: .nativeLimit, machineID: machineID, nativeState: reading.state)
    }
    public func prepareForControl() throws {
        guard pinned != nil else { throw NativeChargeError(code: -3) }
        // Unlike the SMC switch, native activation must not reset an existing limit.
    }
    public func setChargeLimit(_ limit: Int?) throws {
        let target = limit ?? 100
        guard let pinned, pinned.supportedLimits.contains(target) else { throw NativeChargeError(code: -4) }
        let reading = try checkedReading()
        guard reading.supportedLimits.contains(target) else { throw NativeChargeError(code: -4) }
        if reading.state == NativeChargeState(enabled: target < 100, limit: target) { return }
        guard reading.calibrationOverride == false else { throw NativeChargeError(code: -8) }
        try driver.setLimit(target)
        let actual = try checkedReading()
        guard actual.state == NativeChargeState(enabled: target < 100, limit: target) else { throw NativeChargeError(code: -6) }
    }
    public func restore(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid, record.backend == .nativeLimit, record.machineID == identity(), let original = record.nativeState else {
            throw BatteryHardwareError(code: -3)
        }
        let reading = try checkedReading()
        guard reading.supportedLimits.contains(original.limit) else { throw NativeChargeError(code: -4) }
        pinned = .init(backend: .nativeLimit, supportedLimits: reading.supportedLimits, supportsThermalProtection: false)
        if reading.state == original { return }
        guard reading.calibrationOverride == false else { throw NativeChargeError(code: -8) }
        try driver.restore(original)
        guard try checkedReading().state == original else { throw NativeChargeError(code: -6) }
    }
    public func endSession() { pinned = nil }
    public func readSwitch() throws -> UInt8 { try checkedReading().state.enabled ? 2 : 0 }
    public func writeSwitch(_ value: UInt8) throws { throw NativeChargeError(code: -3) }
}

/// Selects using reads only, then pins one implementation for the entire session,
/// including sleep and crash recovery. A failed mutation never triggers fallback.
public final class AppleSiliconChargeHardware: ChargeHardware {
    private let smc: any ChargeHardware
    private let native: any ChargeHardware
    private let nativeAvailable: Bool
    private var selected: (any ChargeHardware)?
    private var selectedBackend: BatteryControlBackend?
    public convenience init() {
        self.init(smc: SMCChargeHardware(), native: NativeChargeHardware(),
                  nativeAvailable: Self.supportsNativeLimit(ProcessInfo.processInfo.operatingSystemVersion))
    }
    init(smc: any ChargeHardware, native: any ChargeHardware, nativeAvailable: Bool) {
        self.smc = smc; self.native = native; self.nativeAvailable = nativeAvailable
    }
    public static func supportsNativeLimit(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 4)
    }
    private func discover() throws -> any ChargeHardware {
        do { _ = try smc.readSwitch(); return smc }
        catch {
            guard nativeAvailable else { throw error }
            _ = try native.readSwitch()
            return native
        }
    }
    private func current() throws -> any ChargeHardware { if let selected { return selected }; return try discover() }
    public var capabilities: BatteryControlCapabilities {
        (try? current().capabilities) ?? .init(backend: .legacyPair, supportedLimits: [], supportsThermalProtection: false)
    }
    public var firmwareManaged: Bool { capabilities.backend == .firmware }
    public func captureRecovery() throws -> BatteryRecoveryRecord {
        let hardware = try discover()
        let record = try hardware.captureRecovery()
        selected = hardware; selectedBackend = record.backend
        return record
    }
    public func restore(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid, selectedBackend == nil || selectedBackend == record.backend else { throw BatteryHardwareError(code: -3) }
        let hardware = record.backend == .nativeLimit ? native : smc
        selected = hardware; selectedBackend = record.backend
        try hardware.restore(record)
    }
    public func prepareForControl() throws { guard let selected else { throw BatteryHardwareError(code: -3) }; try selected.prepareForControl() }
    public func setChargeLimit(_ limit: Int?) throws { guard let selected else { throw BatteryHardwareError(code: -3) }; try selected.setChargeLimit(limit) }
    public func setChargeBand(upper: Int, lower: Int) throws { guard let selected else { throw BatteryHardwareError(code: -3) }; try selected.setChargeBand(upper: upper, lower: lower) }
    public func setFirmwareLimit(_ limit: Int?) throws { try setChargeLimit(limit) }
    public func readSwitch() throws -> UInt8 { try current().readSwitch() }
    public func writeSwitch(_ value: UInt8) throws { guard let selected else { throw BatteryHardwareError(code: -3) }; try selected.writeSwitch(value) }
    public func endSession() { selected?.endSession(); selected = nil; selectedBackend = nil }
}
