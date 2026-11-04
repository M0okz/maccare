import Foundation
import IOKit
import CMacCareSMC

public protocol ChargeHardware {
    var firmwareManaged: Bool { get }
    var capabilities: BatteryControlCapabilities { get }
    func captureRecovery() throws -> BatteryRecoveryRecord
    func restore(_ record: BatteryRecoveryRecord) throws
    func validateDischarge() throws
    func setDischarging(_ disabled: Bool) throws
    func endSession()
    func setFirmwareLimit(_ limit: Int?) throws
    func prepareForControl() throws
    func setChargeBand(upper: Int, lower: Int) throws
    func setChargeLimit(_ limit: Int?) throws
    func readSwitch() throws -> UInt8
    func writeSwitch(_ value: UInt8) throws
    func applyChargeIntent(_ intent: BatteryChargeIntent, snapshot: BatterySnapshot, now: TimeInterval) throws
    func chargeApplicationStatus(now: TimeInterval) throws -> BatteryChargeApplicationStatus?
}

public extension ChargeHardware {
    var firmwareManaged: Bool { false }
    var capabilities: BatteryControlCapabilities {
        .init(backend: firmwareManaged ? .firmware : .legacyPair)
    }
    func prepareForControl() throws { try writeSwitch(0) }
    func setChargeBand(upper: Int, lower: Int) throws {
        guard lower == upper - 3 else { throw BatteryHardwareError(code: -1) }
        try setChargeLimit(upper)
    }
    func setChargeLimit(_ limit: Int?) throws { try setFirmwareLimit(limit) }
    func setFirmwareLimit(_ limit: Int?) throws { throw BatteryHardwareError(code: -1) }
    func captureRecovery() throws -> BatteryRecoveryRecord {
        guard try readSwitch() == 0 else { throw BatteryHardwareError(code: -2) }
        return .init(backend: firmwareManaged ? .firmware : .legacyPair,
                     firmwareUpper: firmwareManaged ? 100 : nil, firmwareLower: firmwareManaged ? 97 : nil)
    }
    func restore(_ record: BatteryRecoveryRecord) throws { if try readSwitch() != 0 { try writeSwitch(0) } }
    func validateDischarge() throws {}
    func setDischarging(_ disabled: Bool) throws { if disabled { throw BatteryHardwareError(code: -1) } }
    func endSession() {}
    func applyChargeIntent(_ intent: BatteryChargeIntent, snapshot: BatterySnapshot, now: TimeInterval) throws {
        throw BatteryHardwareError(code: -1)
    }
    func chargeApplicationStatus(now: TimeInterval) throws -> BatteryChargeApplicationStatus? { nil }
}

/// All accesses occur on the helper's battery queue. A backend is pinned before the
/// recovery record is persisted and stays pinned until restoration has been verified.
public final class SMCChargeHardware: ChargeHardware {
    private var pinned: BatteryControlBackend?
    public init() {}
    private func discover() throws -> BatteryControlBackend {
        var raw: Int32 = 0
        let result = maccare_charge_probe(&raw)
        guard result == 0, let backend = BatteryControlBackend(rawValue: raw) else {
            throw BatteryHardwareError(code: result == 0 ? -1 : result)
        }
        return backend
    }
    public var firmwareManaged: Bool { (try? selectedBackend()) == .firmware }
    public var capabilities: BatteryControlCapabilities {
        .init(backend: (try? selectedBackend()) ?? .legacyPair)
    }
    private func selectedBackend() throws -> BatteryControlBackend { try pinned ?? discover() }

    public func captureRecovery() throws -> BatteryRecoveryRecord {
        guard let machineID = BatteryMachine.identity else { throw BatteryHardwareError(code: -3) }
        let backend = try discover()
        var current: UInt8 = 0
        let result = maccare_charge_read(backend.rawValue, &current)
        guard result == 0 else { throw BatteryHardwareError(code: result) }
        guard current == 0 else { throw BatteryHardwareError(code: -2) }
        let record: BatteryRecoveryRecord
        if backend == .firmware {
            var active: UInt8 = 0; var upper: UInt32 = 0; var lower: UInt32 = 0
            let result = maccare_firmware_limit_read(&active, &upper, &lower)
            guard result == 0, active == 0 else { throw BatteryHardwareError(code: result == 0 ? -2 : result) }
            record = .init(backend: backend, machineID: machineID, firmwareUpper: upper, firmwareLower: lower)
        } else { record = .init(backend: backend, machineID: machineID) }
        pinned = backend
        return record
    }
    public func restore(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid, let identity = BatteryMachine.identity, record.machineID == identity else { throw BatteryHardwareError(code: -3) }
        pinned = record.backend
        if record.backend == .firmware {
            guard let upper = record.firmwareUpper, let lower = record.firmwareLower else { throw BatteryHardwareError(code: -3) }
            var active: UInt8 = 0; var actualUpper: UInt32 = 0; var actualLower: UInt32 = 0
            let read = maccare_firmware_limit_read(&active, &actualUpper, &actualLower)
            guard read == 0 else { throw BatteryHardwareError(code: read) }
            if active != 0 || actualUpper != upper || actualLower != lower {
                let result = maccare_firmware_limit_restore(upper, lower)
                guard result == 0 else { throw BatteryHardwareError(code: result) }
            }
        } else if try readSwitch() != 0 { try writeSwitch(0) }
        guard try readSwitch() == 0 else { throw BatteryHardwareError(code: -1) }
    }
    public func endSession() { pinned = nil }
    public func setChargeBand(upper: Int, lower: Int) throws {
        guard pinned == .firmware, (50...100).contains(upper), (30..<upper).contains(lower) else { throw BatteryHardwareError(code: -1) }
        var active: UInt8 = 0; var actualUpper: UInt32 = 0; var actualLower: UInt32 = 0
        let read = maccare_firmware_limit_read(&active, &actualUpper, &actualLower)
        guard read == 0 else { throw BatteryHardwareError(code: read) }
        if active == 2 && actualUpper == upper && actualLower == lower { return }
        let result = maccare_firmware_limit_set(UInt32(upper), UInt32(lower), 2)
        guard result == 0 else { throw BatteryHardwareError(code: result) }
    }
    public func setFirmwareLimit(_ limit: Int?) throws {
        guard pinned == .firmware else { throw BatteryHardwareError(code: -1) }
        if let limit, !(50...100).contains(limit) { throw BatteryHardwareError(code: -1) }
        var active: UInt8 = 0; var upper: UInt32 = 0; var lower: UInt32 = 0
        let read = maccare_firmware_limit_read(&active, &upper, &lower)
        guard read == 0 else { throw BatteryHardwareError(code: read) }
        if let limit {
            if active == 2 && upper == UInt32(limit) && lower == UInt32(limit - 3) { return }
        } else if active == 0 { return }
        let result = maccare_firmware_limit_set(UInt32(limit ?? 100), UInt32((limit ?? 100) - 3), limit == nil ? 0 : 2)
        guard result == 0 else { throw BatteryHardwareError(code: result) }
    }
    public func readSwitch() throws -> UInt8 {
        var value: UInt8 = 0
        let result = maccare_charge_read(try selectedBackend().rawValue, &value)
        guard result == 0 else { throw BatteryHardwareError(code: result) }
        return value
    }
    public func writeSwitch(_ value: UInt8) throws {
        guard let pinned, value == 0 || value == 2 else { throw BatteryHardwareError(code: -1) }
        let result: Int32
        if pinned == .firmware {
            guard value == 0 else { throw BatteryHardwareError(code: -1) }
            result = maccare_firmware_limit_set(100, 97, 0)
        } else { result = maccare_charge_write(pinned.rawValue, value) }
        guard result == 0 else { throw BatteryHardwareError(code: result) }
    }
}

public struct BatteryHardwareError: LocalizedError {
    public let code: Int32
    public var errorDescription: String? {
        switch code {
        case kIOReturnNotPrivileged: return "macOS refuse la méthode de contrôle utilisée par cette version de MacCare. Utilisez la limite native dans les réglages Batterie si elle est proposée."
        case -2: return "La charge est déjà contrôlée. Désactivez l’autre contrôleur avant d’activer MacCare."
        case -3: return "L’état de restauration de la batterie est invalide. Aucun autre mécanisme matériel ne sera essayé."
        default: return "Cette version de MacCare ne peut pas contrôler la charge sur ce Mac (code \(code)). Utilisez la limite native de macOS si elle est proposée."
        }
    }
}
