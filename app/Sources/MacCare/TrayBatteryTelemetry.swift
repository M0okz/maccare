import Foundation
import IOKit
import IOKit.ps
import Darwin

struct TrayBatteryTelemetry: Sendable {
    struct Accessory: Identifiable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let percent: Int
    }
    struct Consumer: Sendable {
        let name: String
        let value: Double
        let measuredPower: Bool
        var executable: String? = nil
        var appBundlePath: String? {
            guard let executable, executable.hasPrefix("/"), let range = executable.range(of: ".app/") else { return nil }
            return String(executable[..<range.lowerBound]) + ".app"
        }
        var formattedValue: String {
            if measuredPower {
                if value > 0 && value < 0.01 { return "< 0,01 W" }
                return value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(value < 1 ? 2 : 1))) + " W"
            }
            if value > 0 && value < 0.1 { return "< 0,1 %" }
            return value.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(1))) + " %"
        }
    }
    var adapterWatts: Double?
    var accessories: [Accessory] = []
    var consumer: Consumer?

    static func adapterPower(_ details: [String: Any]) -> Double? {
        guard let value = details[kIOPSPowerAdapterWattsKey] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
              value.doubleValue > 0, value.doubleValue <= 1000 else { return nil }
        return value.doubleValue
    }

    static func accessory(id: UInt64, properties: [String: Any]) -> Accessory? {
        guard let value = properties["BatteryPercent"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
              (0...100).contains(value.doubleValue),
              let name = properties["Product"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lower = name.lowercased()
        let isChargingCase = lower.contains("boîtier") || lower.contains("boitier") || (lower.contains("airpod") && lower.contains("case"))
        let symbol = isChargingCase ? "airpods.chargingcase" :
            lower.contains("mouse") || lower.contains("souris") ? "computermouse" :
            lower.contains("keyboard") || lower.contains("clavier") ? "keyboard" :
            lower.contains("iphone") ? "iphone" : lower.contains("ipad") ? "ipad" :
            lower.contains("airpod") || lower.contains("headphone") ? "headphones" : "battery.100percent"
        return .init(id: "hid:\(id)", name: name, symbol: symbol, percent: Int(value.doubleValue.rounded()))
    }

    static func powerSourceAccessory(id: UInt64, properties: [String: Any]) -> Accessory? {
        if let present = properties[kIOPSIsPresentKey] as? Bool, !present { return nil }
        guard let name = properties[kIOPSNameKey] as? String,
              let current = properties[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = properties[kIOPSMaxCapacityKey] as? NSNumber,
              CFGetTypeID(current) != CFBooleanGetTypeID(), CFGetTypeID(maximum) != CFBooleanGetTypeID(),
              current.doubleValue.isFinite, maximum.doubleValue.isFinite, maximum.doubleValue > 0,
              current.doubleValue >= 0, current.doubleValue <= maximum.doubleValue,
              let device = accessory(id: id, properties: ["Product": name, "BatteryPercent": current.doubleValue / maximum.doubleValue * 100]) else { return nil }
        return .init(id: "power:\(id)", name: device.name, symbol: device.symbol, percent: device.percent)
    }

    static func leadingConsumer(_ processes: [TrayProcess]) -> Consumer? {
        let processes = processes.filter { process in
            guard process.id.pid != getpid() else { return false }
            let path = URL(fileURLWithPath: process.executable)
            let ownExecutables = ["MacCare", "MacCareHelper", "org.maccare.helper"]
            if ownExecutables.contains(path.lastPathComponent) { return false }
            if process.executable.isEmpty && ownExecutables.contains(process.name) { return false }
            return !path.pathComponents.contains(where: { $0 == "MacCare.app" || $0 == "MacCare Dev.app" })
        }
        if let process = processes.filter({ ($0.energyWatts ?? 0) > 0 }).max(by: { ($0.energyWatts ?? 0) < ($1.energyWatts ?? 0) }), let watts = process.energyWatts {
            return .init(name: process.name, value: watts, measuredPower: true, executable: process.executable)
        }
        if let process = processes.filter({ ($0.cpuPercent ?? 0) > 0 }).max(by: { ($0.cpuPercent ?? 0) < ($1.cpuPercent ?? 0) }), let cpu = process.cpuPercent {
            return .init(name: process.name, value: cpu, measuredPower: false, executable: process.executable)
        }
        return nil
    }
}

actor TrayBatterySampler {
    private let processes = TrayProcessSampler()
    private var processCadence = TrayBatteryProcessCadence()
    private var consumer: TrayBatteryTelemetry.Consumer?
    private var readingProcesses = false

    func read() async -> TrayBatteryTelemetry {
        var result = TrayBatteryTelemetry()
        if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            result.adapterWatts = TrayBatteryTelemetry.adapterPower(details)
        }
        result.accessories = accessorySources()
        // Repli sur les services HID déjà présents : aucune recherche ni appairage.
        var iterator: io_iterator_t = 0
        if result.accessories.isEmpty && IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
                var properties: Unmanaged<CFMutableDictionary>?
                var id: UInt64 = 0
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                   let values = properties?.takeRetainedValue() as? [String: Any],
                   let accessory = TrayBatteryTelemetry.accessory(id: id, properties: values) {
                    result.accessories.append(accessory)
                }
            }
        }
        result.accessories.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        if !readingProcesses && processCadence.shouldSample(at: ProcessInfo.processInfo.systemUptime) {
            readingProcesses = true
            let sample = await processes.sample(includeEnergy: true,
                                               maximumInterval: TrayBatteryProcessCadence.maximumMeasurementInterval)
            consumer = TrayBatteryTelemetry.leadingConsumer(sample)
            readingProcesses = false
        }
        result.consumer = consumer
        return result
    }
    private func accessorySources() -> [TrayBatteryTelemetry.Accessory] {
        // ABI publié par Apple dans IOKitUser/ps.subproj/IOPowerSourcesPrivate.h.
        // L’API est optionnelle ; sa disparition ne bloque pas le volet.
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return [] }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return [] }
        typealias CopySources = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        let copy = unsafeBitCast(symbol, to: CopySources.self)
        guard let info = copy(4)?.takeRetainedValue() else { return [] } // kIOPSSourceForAccessories
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.enumerated().compactMap { index, source in
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return nil }
            let id = (source as? NSNumber)?.uint64Value ?? UInt64(index)
            return TrayBatteryTelemetry.powerSourceAccessory(id: id, properties: values)
        }
    }

}
