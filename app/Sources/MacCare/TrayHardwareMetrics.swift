import Foundation
import IOKit
import CMacCareSMC

struct TrayGPU: Sendable {
    let id: UInt64
    let model: String
    let cores: Int?
    let fraction: Double?
    var temperature: Double?

    static func utilization(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        return percent.isFinite && (0...100).contains(percent) ? percent / 100 : nil
    }

    static func current() -> TrayGPU? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var candidates: [TrayGPU] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            let stats = property("PerformanceStatistics") as? [String: Any]
            let cores = (property("gpu-core-count") as? NSNumber)?.intValue
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            candidates.append(.init(id: id, model: property("model") as? String ?? "GPU",
                                    cores: cores.flatMap { (1...1024).contains($0) ? $0 : nil },
                                    fraction: utilization(stats?["Device Utilization %"])))
        }
        // Une carte complète : ne pas mélanger charge et caractéristiques de deux GPU.
        return candidates.max { ($0.fraction ?? -1) < ($1.fraction ?? -1) }
    }
}

struct TrayFans: Sendable {
    struct Fan: Sendable {
        let rpm: Double?
        let maximum: Double?
        var load: Double? {
            guard let rpm, let maximum, maximum > 0 else { return nil }
            return min(1, max(0, rpm / maximum))
        }
    }
    let fans: [Fan]
    var fastest: Double? { fans.compactMap(\.rpm).max() }
    var load: Double? { fans.compactMap(\.load).max() }
    var state: String {
        if fans.isEmpty { return "Aucun ventilateur" }
        guard fans.allSatisfy({ $0.rpm != nil }) else { return "Lecture partielle" }
        return fastest == 0 ? "À l’arrêt · macOS" : "Actifs · macOS"
    }
    static func current() -> TrayFans? {
        var snapshot = MCFanSnapshot()
        guard maccare_fans_read(&snapshot) == 0, snapshot.count <= 8 else { return nil }
        let current = withUnsafeBytes(of: snapshot.current) { Array($0.bindMemory(to: Double.self)) }
        let maximum = withUnsafeBytes(of: snapshot.maximum) { Array($0.bindMemory(to: Double.self)) }
        let valid = withUnsafeBytes(of: snapshot.currentValid) { Array($0) }
        let maxValid = withUnsafeBytes(of: snapshot.maximumValid) { Array($0) }
        return .init(fans: (0..<Int(snapshot.count)).map {
            .init(rpm: valid[$0] != 0 ? current[$0] : nil, maximum: maxValid[$0] != 0 ? maximum[$0] : nil)
        })
    }
    var description: String {
        fans.enumerated().map { index, fan in
            "Ventilateur \(index + 1) : \(fan.rpm.map { "\(Int($0.rounded())) tr/min" } ?? "indisponible")"
        }.joined(separator: "\n")
    }
}

struct TrayGPUHistory {
    private(set) var points: [TrayHistoryPoint] = []
    private var id: UInt64?
    mutating func record(_ metrics: TrayMetrics) {
        if id != metrics.gpu?.id { points = []; id = metrics.gpu?.id }
        points.removeAll { $0.time < metrics.sampledAt - TrayCPUHistory.duration - 1 }
        guard let value = metrics.gpu?.fraction, value.isFinite else { return }
        points.append(.init(time: metrics.sampledAt, value: min(1, max(0, value))))
    }
}
