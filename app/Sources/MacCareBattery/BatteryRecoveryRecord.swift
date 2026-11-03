import Foundation

public enum BatteryControlBackend: Int32, Codable, Sendable {
    case legacyPair = 1, chargeGate = 2, firmware = 3, nativeLimit = 4
}

public struct NativeChargeState: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let limit: Int
    public init(enabled: Bool, limit: Int) { self.enabled = enabled; self.limit = limit }
    public var isValid: Bool { (80...100).contains(limit) }
}

/// Durable ownership record: restoration never discovers or substitutes a different backend.
public struct BatteryRecoveryRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let machineID: String
    public let backend: BatteryControlBackend
    public let firmwareUpper: UInt32?
    public let firmwareLower: UInt32?
    public let adapterBackend: BatteryAdapterBackend?
    public let nativeState: NativeChargeState?
    public init(backend: BatteryControlBackend, machineID: String = "fixture", firmwareUpper: UInt32? = nil,
                firmwareLower: UInt32? = nil, nativeState: NativeChargeState? = nil, adapterBackend: BatteryAdapterBackend? = nil) {
        version = adapterBackend != nil || (backend != .nativeLimit && nativeState != nil) ? 3 : (backend == .nativeLimit ? 2 : 1)
        self.machineID = machineID; self.backend = backend
        self.firmwareUpper = firmwareUpper; self.firmwareLower = firmwareLower; self.nativeState = nativeState; self.adapterBackend = adapterBackend
    }
    public var isValid: Bool {
        guard !machineID.isEmpty, machineID.utf8.count <= 128 else { return false }
        if version == 3, adapterBackend == nil, (backend == .nativeLimit || nativeState == nil) { return false }
        if version != 3 && adapterBackend != nil { return false }
        if let nativeState, !nativeState.isValid || nativeState.enabled != (nativeState.limit < 100) { return false }
        if backend == .nativeLimit {
            guard version == 2 || version == 3, let nativeState, nativeState.isValid, firmwareUpper == nil, firmwareLower == nil else { return false }
            return nativeState.enabled == (nativeState.limit < 100)
        }
        guard version == 1 || version == 3, version == 3 || nativeState == nil else { return false }
        if backend == .firmware {
            guard let upper = firmwareUpper, let lower = firmwareLower else { return false }
            return upper <= 100 && lower <= 100
        }
        return firmwareUpper == nil && firmwareLower == nil
    }
}
