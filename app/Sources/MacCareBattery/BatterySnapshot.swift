import Foundation
import IOKit
import IOKit.ps
import CMacCareSMC

public struct BatterySnapshot: Codable, Sendable {
    public var present: Bool
    public var appleSilicon: Bool
    public var percent: Int?
    public var onAC: Bool
    public var batteryFault: Bool
    public var powerStateKnown: Bool
    public var charging: Bool
    public var cycles: Int?
    public var healthPercent: Int?
    public var temperature: Double?
    /// Télémétrie IOPS informative uniquement ; aucune incidence sur le contrôle de charge.
    public var healthState: String?
    public var minutesRemaining: Int?

    public init(present: Bool = true, appleSilicon: Bool = true, percent: Int? = nil,
                onAC: Bool = false, charging: Bool = false, cycles: Int? = nil,
                healthPercent: Int? = nil, temperature: Double? = nil, powerStateKnown: Bool = true, batteryFault: Bool = false) {
        self.batteryFault = batteryFault
        self.powerStateKnown = powerStateKnown
        self.present = present; self.appleSilicon = appleSilicon; self.percent = percent
        self.onAC = onAC; self.charging = charging; self.cycles = cycles
        self.healthPercent = healthPercent; self.temperature = temperature
    }

    public var reliableTemperature: Bool {
        guard let temperature else { return false }
        return temperature.isFinite && temperature > 0 && temperature <= 90
    }
    public var reliableForControl: Bool {
        present && appleSilicon && !batteryFault && powerStateKnown && percent.map { (0...100).contains($0) } == true
    }

    public static func read() -> Self {
        var silicon: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let isSilicon = sysctlbyname("hw.optional.arm64", &silicon, &size, nil, 0) == 0 && silicon == 1
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return .init(present: false, appleSilicon: isSilicon) }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = properties?.takeRetainedValue() as? [String: Any] else {
            return .init(present: true, appleSilicon: isSilicon, powerStateKnown: false)
        }
        var result = decode(d, appleSilicon: isSilicon)
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let descriptions = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
        result = result.applyingPowerSources(descriptions)
        if result.temperature == nil {
            let pack = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBatteryPack"))
            if pack != 0 {
                if let data = IORegistryEntryCreateCFProperty(pack, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                    result.temperature = decode(["BatteryData": data], appleSilicon: isSilicon).temperature
                }
                IOObjectRelease(pack)
            }
        }
        if result.temperature == nil {
            var temperature: Double = 0
            if maccare_battery_temperature(&temperature) == 0 { result.temperature = temperature }
        }
        return result
    }

    /// Use the macOS internal-battery percentage for control, never an attached UPS.
    /// Registry capacities remain informational if IOPS cannot confirm a coherent state.
    public func applyingPowerSources(_ descriptions: [[String: Any]]) -> Self {
        var result = self
        result.powerStateKnown = false
        result.healthState = nil; result.minutesRemaining = nil
        guard let source = descriptions.first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }) else { return result }
        let values: [String: Any] = [
            "CurrentCapacity": source[kIOPSCurrentCapacityKey] as Any,
            "MaxCapacity": source[kIOPSMaxCapacityKey] as Any,
            "BatteryInstalled": source[kIOPSIsPresentKey] as? Bool ?? true,
            "ExternalConnected": source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            "IsCharging": source[kIOPSIsChargingKey] as Any
        ]
        let decoded = Self.decode(values, appleSilicon: appleSilicon)
        let state = source[kIOPSPowerSourceStateKey] as? String
        result.percent = decoded.percent; result.present = decoded.present
        result.onAC = decoded.onAC; result.charging = decoded.charging
        result.powerStateKnown = decoded.powerStateKnown && (state == kIOPSACPowerValue || state == kIOPSBatteryPowerValue)
        result.healthState = source[kIOPSBatteryHealthConditionKey] as? String ?? source[kIOPSBatteryHealthKey] as? String
        if result.powerStateKnown && !result.onAC && !result.charging,
           let value = source[kIOPSTimeToEmptyKey] as? NSNumber,
           CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
           value.doubleValue > 0, value.doubleValue < Double(Int.max) {
            result.minutesRemaining = value.intValue
        }
        return result
    }

    /// Kept separate from IOKit to verify units and missing telemetry using fixtures.
    public static func decode(_ d: [String: Any], appleSilicon: Bool) -> Self {
        let battery = d["BatteryData"] as? [String: Any] ?? [:]
        func number(in values: [String: Any], _ key: String) -> Double? {
            guard let n = values[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        func number(_ key: String) -> Double? { number(in: d, key) ?? number(in: battery, key) }
        func boolean(_ key: String) -> Bool? {
            guard let n = d[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        }
        // Never mix a top-level percentage with a nested raw capacity in different units.
        func percentage(in values: [String: Any]) -> Int? {
            guard let current = number(in: values, "CurrentCapacity"), let maximum = number(in: values, "MaxCapacity"),
                  maximum > 0, current >= 0, current <= maximum else { return nil }
            let ratio = current / maximum * 100
            guard ratio.isFinite else { return nil }
            return Int(ratio.rounded())
        }
        let percent = percentage(in: d) ?? percentage(in: battery)
        let full = number("AppleRawMaxCapacity") ?? number("FullChargeCapacity") ?? number("NominalChargeCapacity")
        let design = number("DesignCapacity")
        let health: Int? = full.flatMap { full in
            guard let design, design > 0, full > 0 else { return nil }
            let ratio = min(100, full / design * 100)
            guard ratio.isFinite else { return nil }
            return Int(ratio.rounded())
        }
        // AppleSmartBattery Temperature is centi-degrees Celsius, not ambient temperature.
        let temperature = number("Temperature").flatMap { raw -> Double? in
            let celsius = raw / 100
            return celsius > 0 && celsius <= 90 ? celsius : nil
        }
        return .init(present: boolean("BatteryInstalled") ?? false, appleSilicon: appleSilicon,
                     percent: percent, onAC: boolean("ExternalConnected") ?? false,
                     charging: boolean("IsCharging") ?? false,
                     cycles: number("CycleCount").flatMap { $0 >= 0 && $0 < Double(Int.max) ? Int($0) : nil },
                     healthPercent: health, temperature: temperature,
                     powerStateKnown: boolean("ExternalConnected") != nil && boolean("IsCharging") != nil,
                     batteryFault: number("PermanentFailureStatus").map { $0 != 0 } ?? false)
    }
}
