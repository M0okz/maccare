import Foundation

public struct BatteryConfiguration: Codable, Equatable, Sendable {
    public var limit: Int
    public var thermalProtection: Bool
    public var maximumTemperature: Int
    /// Nil retains the standard hysteresis. Otherwise pause within this band from activation.
    public var sailingWidth: Int?
    public init(limit: Int = 80, thermalProtection: Bool = true, maximumTemperature: Int = 35, sailingWidth: Int? = nil) {
        self.limit = limit; self.thermalProtection = thermalProtection; self.maximumTemperature = maximumTemperature; self.sailingWidth = sailingWidth
    }
    public var isValid: Bool {
        (50...100).contains(limit) && (30...45).contains(maximumTemperature) &&
        sailingWidth.map { (2...20).contains($0) && limit - $0 >= 30 } != false
    }
    public var resumeLimit: Int { limit - (sailingWidth ?? 3) }
}

public enum BatteryCommand: String, Codable, Sendable { case status, heartbeat, enable, disable, topUp, cancelTopUp, discharge, calibrate, cancelCycle }

public enum BatteryControlLimitation: String, Codable, Sendable { case hardwareAccessDenied }

public struct BatteryControlCapabilities: Codable, Equatable, Sendable {
    public let backend: BatteryControlBackend
    public let supportedLimits: [Int]
    public let adapterBackend: BatteryAdapterBackend?
    public let limitation: BatteryControlLimitation?
    public var supportsDischarge: Bool { adapterBackend != nil }
    public let supportsThermalProtection: Bool
    public init(backend: BatteryControlBackend, supportedLimits: [Int]? = nil, supportsThermalProtection: Bool? = nil, adapterBackend: BatteryAdapterBackend? = nil, limitation: BatteryControlLimitation? = nil) {
        self.backend = backend; self.adapterBackend = adapterBackend
        self.limitation = limitation
        self.supportedLimits = supportedLimits ?? Array(backend == .nativeLimit ? 80...100 : 50...100)
        self.supportsThermalProtection = supportsThermalProtection ?? (backend == .legacyPair || backend == .chargeGate)
    }
    public var supportsSailing: Bool { backend != .nativeLimit }
    public var managesChargeLimit: Bool { backend == .firmware || backend == .nativeLimit }
    public var isValid: Bool {
        let allowed = backend == .nativeLimit ? 80...100 : 50...100
        return !supportedLimits.isEmpty && supportedLimits.count <= 51
            && supportedLimits == supportedLimits.sorted() && Set(supportedLimits).count == supportedLimits.count
            && supportedLimits.allSatisfy(allowed.contains) && (!managesChargeLimit || !supportsThermalProtection)
    }
}

public struct BatteryProtectionStatus: Codable, Sendable {
    public var snapshot: BatterySnapshot
    public var firmwareManaged: Bool
    public var restoring: Bool
    public var ownedByCaller: Bool
    public var recoveryReady: Bool = false
    public var supported: Bool
    public var active: Bool
    public var suspended: Bool
    public var topUp: Bool
    public var configuration: BatteryConfiguration?
    public var message: String
    public var error: String?
    public var cycle: BatteryCycleStatus? = nil
    public var capabilities: BatteryControlCapabilities?
    public init(snapshot: BatterySnapshot, firmwareManaged: Bool = false, supported: Bool = false, active: Bool = false,
                suspended: Bool = false, topUp: Bool = false, configuration: BatteryConfiguration? = nil,
                message: String = "Protection désactivée", error: String? = nil, restoring: Bool = false, ownedByCaller: Bool = false,
                capabilities: BatteryControlCapabilities? = nil) {
        self.restoring = restoring; self.ownedByCaller = ownedByCaller
        self.snapshot = snapshot; self.firmwareManaged = firmwareManaged; self.supported = supported; self.active = active
        self.suspended = suspended; self.topUp = topUp; self.configuration = configuration
        self.message = message; self.error = error; self.capabilities = capabilities
    }
}

/// Pure control policy. Separate hysteresis prevents rapid charge/thermal oscillations.
public struct BatteryProtectionPolicy: Sendable {
    public private(set) var limitReached = false
    public private(set) var tooHot = false
    private var initializedBand = false
    public init() {}
    public mutating func evaluate(_ snapshot: BatterySnapshot, configuration: BatteryConfiguration,
                                  topUp: Bool) -> (suspend: Bool, reason: String) {
        guard snapshot.reliableForControl, let percent = snapshot.percent else {
            return (false, "Mesures de batterie indisponibles : charge rendue à macOS.")
        }
        guard snapshot.onAC else {
            limitReached = false; tooHot = false; initializedBand = false
            return (false, "Sur batterie · protection en attente du secteur")
        }
        if configuration.thermalProtection {
            guard snapshot.reliableTemperature, let temperature = snapshot.temperature else {
                tooHot = true
                return (true, "Charge suspendue · température indisponible")
            }
            if temperature >= Double(configuration.maximumTemperature) { tooHot = true }
            if temperature <= Double(configuration.maximumTemperature - 2) { tooHot = false }
        } else { tooHot = false }
        if !initializedBand, configuration.sailingWidth != nil { limitReached = percent > configuration.resumeLimit }
        initializedBand = true
        if percent >= configuration.limit { limitReached = true }
        if percent <= configuration.resumeLimit { limitReached = false }
        if tooHot { return (true, "Charge suspendue · protection thermique") }
        if topUp { return (false, configuration.thermalProtection
            ? "Recharge ponctuelle à 100 % · protection thermique conservée" : "Recharge ponctuelle à 100 %") }
        if limitReached { return (true, "Charge suspendue · limite de \(configuration.limit) % atteinte") }
        return (false, "Charge autorisée jusqu’à \(configuration.limit) %")
    }
}
