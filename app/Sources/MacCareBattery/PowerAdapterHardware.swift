import Foundation
import CMacCareSMC

public enum BatteryAdapterBackend: Int32, Codable, Sendable { case legacy = 1, modern = 2 }

public protocol PowerAdapterDriver {
    func discover() throws -> BatteryAdapterBackend
    func read(_ backend: BatteryAdapterBackend) throws -> Bool
    func write(_ backend: BatteryAdapterBackend, disabled: Bool) throws
}

public struct SystemPowerAdapterDriver: PowerAdapterDriver {
    public init() {}
    public func discover() throws -> BatteryAdapterBackend {
        var raw: Int32 = 0
        let result = maccare_adapter_probe(&raw)
        guard result == 0, let value = BatteryAdapterBackend(rawValue: raw) else { throw BatteryHardwareError(code: result == 0 ? -3 : result) }
        return value
    }
    public func read(_ backend: BatteryAdapterBackend) throws -> Bool {
        var raw: UInt8 = 0
        let result = maccare_adapter_read(backend.rawValue, &raw)
        guard result == 0, raw <= 1 else { throw BatteryHardwareError(code: result == 0 ? -3 : result) }
        return raw == 1
    }
    public func write(_ backend: BatteryAdapterBackend, disabled: Bool) throws {
        let result = maccare_adapter_write(backend.rawValue, disabled ? 1 : 0)
        guard result == 0 else { throw BatteryHardwareError(code: result) }
    }
}

/// Records ownership of adapter isolation in the same durable transaction as the
/// charge limit. On every exit, restoring external input precedes charge restoration.
public final class RecoverableChargeHardware: ChargeHardware {
    private let base: any ChargeHardware
    private let adapter: any PowerAdapterDriver
    private let identity: () -> String?
    private var pinnedAdapter: BatteryAdapterBackend?
    private var captured = false
    public convenience init(base: any ChargeHardware = AppleSiliconChargeHardware(), adapter: any PowerAdapterDriver = SystemPowerAdapterDriver()) {
        self.init(base: base, adapter: adapter, identity: { BatteryMachine.identity })
    }
    public init(base: any ChargeHardware, adapter: any PowerAdapterDriver, identity: @escaping () -> String?) {
        self.base = base; self.adapter = adapter; self.identity = identity
    }
    public var capabilities: BatteryControlCapabilities {
        let value = base.capabilities
        return .init(backend: value.backend, supportedLimits: value.supportedLimits,
                     supportsThermalProtection: value.supportsThermalProtection,
                     adapterBackend: captured ? pinnedAdapter : try? adapter.discover(), limitation: value.limitation)
    }
    public var firmwareManaged: Bool { base.firmwareManaged }
    public func captureRecovery() throws -> BatteryRecoveryRecord {
        let backend = capabilities.adapterBackend
        if let backend, try adapter.read(backend) { throw BatteryHardwareError(code: -2) }
        let record = try base.captureRecovery()
        // The policy pulses this gate after each write, so it must be able to restore it.
        if record.backend == .nativePolicy, backend == nil { base.endSession(); throw BatteryNativePolicyError.unavailable }
        pinnedAdapter = backend; captured = true
        return .init(backend: record.backend, machineID: record.machineID, firmwareUpper: record.firmwareUpper,
                     firmwareLower: record.firmwareLower, nativeState: record.nativeState, adapterBackend: backend,
                     nativePolicyPreferences: record.nativePolicyPreferences)
    }
    public func prepareForControl() throws { try base.prepareForControl() }
    public func validateDischarge() throws { try base.validateDischarge() }
    public func setDischarging(_ disabled: Bool) throws {
        guard captured else { throw BatteryHardwareError(code: -3) }
        guard let backend = pinnedAdapter else { if disabled { throw BatteryHardwareError(code: -1) }; return }
        if disabled { try base.validateDischarge() }
        if try adapter.read(backend) != disabled { try adapter.write(backend, disabled: disabled) }
        guard try adapter.read(backend) == disabled else { throw BatteryHardwareError(code: -1) }
    }
    public func restore(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid, record.machineID == identity() else { throw BatteryHardwareError(code: -3) }
        if let backend = record.adapterBackend {
            if try adapter.read(backend) { try adapter.write(backend, disabled: false) }
            guard try adapter.read(backend) == false else { throw BatteryHardwareError(code: -1) }
        }
        try base.restore(record)
    }
    public func setChargeBand(upper: Int, lower: Int) throws { try base.setChargeBand(upper: upper, lower: lower) }
    public func setChargeLimit(_ limit: Int?) throws { try base.setChargeLimit(limit) }
    public func readSwitch() throws -> UInt8 { try base.readSwitch() }
    public func writeSwitch(_ value: UInt8) throws { try base.writeSwitch(value) }
    public func applyChargeIntent(_ intent: BatteryChargeIntent, snapshot: BatterySnapshot, now: TimeInterval) throws {
        try base.applyChargeIntent(intent, snapshot: snapshot, now: now)
    }
    public func chargeApplicationStatus(now: TimeInterval) throws -> BatteryChargeApplicationStatus? {
        try base.chargeApplicationStatus(now: now)
    }
    public func endSession() { base.endSession(); pinnedAdapter = nil; captured = false }
}
