import Foundation
import Darwin
import CoreWLAN
import CMacCareSMC

struct TrayMetrics: Sendable {
    struct CPU: Sendable {
        let user: Double
        let system: Double
        var temperature: Double? = nil
        var used: Double { user + system }
    }
    struct Memory: Sendable {
        let total: UInt64
        let active: UInt64
        let wired: UInt64
        let compressed: UInt64
        var pressure: MemoryPressureLevel? = nil
        var used: UInt64 { min(total, active + wired + compressed) }
        var available: UInt64 { total - used }
        var fraction: Double { Double(used) / Double(max(total, 1)) }
    }
    struct Network: Sendable {
        enum Kind: String, Sendable { case wifi = "Wi-Fi", ethernet = "Ethernet", vpn = "VPN", other = "Réseau" }
        let interface: String
        let powered: Bool
        let connected: Bool
        let linkRate: Double
        let received: Double?
        let sent: Double?
        var signalDBm: Int? = nil
        var kind: Kind = .wifi
        var address: String? = nil
        var symbol: String { kind == .wifi ? "wifi" : kind == .vpn ? "lock.shield" : "network" }
    }
    typealias WiFi = Network
    var network: Network? { wifi }
    var sampledAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    var gpu: TrayGPU?
    var fans: TrayFans?
    var cpu: CPU?
    var memory: Memory?
    var wifi: WiFi?
}

/// Charge CPU globale entre deux lectures des compteurs système.
struct CPULoadCounter {
    private var previous: [UInt32]?

    mutating func reset() { previous = nil }

    mutating func read() -> TrayMetrics.CPU? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { previous = nil; return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previous = ticks }
        guard let previous else { return nil }
        let delta = zip(ticks, previous).map { UInt64($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return .init(user: Double(delta[0] + delta[3]) / Double(total), system: Double(delta[1]) / Double(total))
    }
}

/// Conserve une valeur coûteuse à lire pendant une durée donnée.
struct TrayTimedCache<Value> {
    let lifetime: TimeInterval
    private var stored: (value: Value, readAt: TimeInterval)?

    init(lifetime: TimeInterval) { self.lifetime = lifetime }

    mutating func value(now: TimeInterval, read: () -> Value) -> Value {
        if let stored, now >= stored.readAt, now - stored.readAt < lifetime { return stored.value }
        let value = read()
        stored = (value, now)
        return value
    }

    var cachedValue: Value? { stored?.value }
    mutating func clear() { stored = nil }
}

/// Deux relevés de compteurs sont nécessaires pour les débits et la charge CPU.
/// Les lectures CoreWLAN et Mach restent hors du thread de l’interface.
protocol TrayMetricsSampling: Sendable {
    func reset() async
    func sample(includeSensors: Bool) async -> TrayMetrics
}

struct TrayNetworkCounter {
    struct Reading {
        let name: String
        let address: String?
        let received: UInt32
        let sent: UInt32
        let time: TimeInterval
    }
    private var previous: Reading?

    mutating func rates(_ current: Reading) -> (received: Double?, sent: Double?) {
        defer { previous = current }
        guard let previous, previous.name == current.name, previous.address == current.address,
              current.time > previous.time, current.time - previous.time <= TrayHistoryPoint.maximumGap else { return (nil, nil) }
        let elapsed = current.time - previous.time
        return (Double(current.received &- previous.received) / elapsed, Double(current.sent &- previous.sent) / elapsed)
    }
}

actor TrayMetricsSampler: TrayMetricsSampling {
    private var cpuLoad = CPULoadCounter()
    private var networkCounter = TrayNetworkCounter()
    private struct WiFiLink { let name: String; let powered: Bool; let rate: Double; let rssi: Int }
    /// Chaque lecture CoreWLAN sollicite un service système ; l’état de liaison varie peu.
    private var link = TrayTimedCache<WiFiLink?>(lifetime: 5)
    private var interfaceTypes = TrayTimedCache<[String: String]>(lifetime: 10)
    private var cpuTemperature = TrayTimedCache<Double?>(lifetime: 5)

    private var gpuTemperature = TrayTimedCache<Double?>(lifetime: 5)
    private var fans = TrayTimedCache<TrayFans?>(lifetime: 5)

    func reset() {
        guard !Task.isCancelled else { return }
        cpuLoad.reset()
        networkCounter = .init()
        // Les lectures coûteuses gardent leur durée de validité (5 à 10 s), même
        // lors d’un changement d’onglet. Leurs caches expirent sans minuterie.
    }

    func sample(includeSensors: Bool = true) -> TrayMetrics {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = cpuLoad.read()
        cpu?.temperature = includeSensors ? cpuTemperature.value(now: ProcessInfo.processInfo.systemUptime) {
            var temperature: Double = 0
            return maccare_cpu_temperature(&temperature) == 0 ? temperature : nil
        } : cpuTemperature.cachedValue ?? nil
        let now = ProcessInfo.processInfo.systemUptime
        var gpu = TrayGPU.current()
        gpu?.temperature = includeSensors ? gpuTemperature.value(now: now) {
            var temperature: Double = 0
            return maccare_gpu_temperature(&temperature) == 0 ? temperature : nil
        } : gpuTemperature.cachedValue ?? nil
        return TrayMetrics(sampledAt: now, gpu: gpu,
                           fans: includeSensors ? fans.value(now: now) { TrayFans.current() } : fans.cachedValue ?? nil,
                           cpu: cpu, memory: memory(host: host), wifi: network(includeLink: includeSensors))
    }

    private func memory(host: host_t) -> TrayMetrics.Memory? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let active = UInt64(info.active_count) - min(UInt64(info.active_count), UInt64(info.purgeable_count))
        return .init(total: ProcessInfo.processInfo.physicalMemory,
                     active: active * UInt64(pageSize), wired: UInt64(info.wire_count) * UInt64(pageSize),
                     compressed: UInt64(info.compressor_page_count) * UInt64(pageSize), pressure: MemoryPressureLevel.current())
    }

    private func network(includeLink: Bool) -> TrayMetrics.Network? {
        let now = ProcessInfo.processInfo.systemUptime
        let cached = includeLink ? link.value(now: now) {
            guard let interface = CWWiFiClient.shared().interface(), let name = interface.interfaceName else { return nil }
            return WiFiLink(name: name, powered: interface.powerOn(), rate: interface.transmitRate(), rssi: interface.rssiValue())
        } : link.cachedValue ?? nil
        let types = interfaceTypes.value(now: now) { NetworkInterfaceSample.interfaceTypes() }
        guard let current = NetworkInterfaceSample.current(types: types, wifiName: cached?.name) else {
            networkCounter = .init()
            return nil
        }
        let rates = networkCounter.rates(.init(name: current.name, address: current.address,
                                              received: current.received, sent: current.sent, time: now))
        let wireless = current.kind == .wifi
        return .init(interface: current.name, powered: wireless ? cached?.powered ?? true : true,
                     connected: current.address != nil, linkRate: wireless ? cached?.rate ?? 0 : 0,
                     received: rates.received, sent: rates.sent,
                     signalDBm: wireless && cached?.rssi != 0 ? cached?.rssi : nil,
                     kind: current.kind, address: current.address)
    }
}
