import Foundation
import Darwin
import CoreWLAN

struct TrayMetrics: Sendable {
    struct CPU: Sendable {
        let user: Double
        let system: Double
        var used: Double { user + system }
    }
    struct Memory: Sendable {
        let total: UInt64
        let active: UInt64
        let wired: UInt64
        let compressed: UInt64
        var used: UInt64 { min(total, active + wired + compressed) }
        var available: UInt64 { total - used }
        var fraction: Double { Double(used) / Double(max(total, 1)) }
    }
    struct WiFi: Sendable {
        let interface: String
        let powered: Bool
        let connected: Bool
        let linkRate: Double
        let received: Double?
        let sent: Double?
        var signalDBm: Int? = nil
    }
    var sampledAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    var cpu: CPU?
    var memory: Memory?
    var wifi: WiFi?
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

    mutating func clear() { stored = nil }
}

/// Deux relevés de compteurs sont nécessaires pour les débits et la charge CPU.
/// Les lectures CoreWLAN et Mach restent hors du thread de l’interface.
actor TrayMetricsSampler {
    private var previousCPU: [UInt32]?
    private var previousNetwork: (name: String, received: UInt32, sent: UInt32, time: TimeInterval)?
    private struct WiFiLink { let name: String; let powered: Bool; let rate: Double; let rssi: Int }
    /// Chaque lecture CoreWLAN sollicite un service système ; l’état de liaison varie peu.
    private var link = TrayTimedCache<WiFiLink?>(lifetime: 5)

    func reset() {
        previousCPU = nil
        previousNetwork = nil
        link.clear()
    }

    func sample() -> TrayMetrics {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        return TrayMetrics(cpu: cpu(host: host), memory: memory(host: host), wifi: wifi())
    }

    private func cpu(host: host_t) -> TrayMetrics.CPU? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { previousCPU = nil; return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousCPU = ticks }
        guard let previousCPU else { return nil }
        let delta = zip(ticks, previousCPU).map { UInt64($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return .init(user: Double(delta[0] + delta[3]) / Double(total), system: Double(delta[1]) / Double(total))
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
                     compressed: UInt64(info.compressor_page_count) * UInt64(pageSize))
    }

    private func wifi() -> TrayMetrics.WiFi? {
        let cached = link.value(now: ProcessInfo.processInfo.systemUptime) {
            guard let interface = CWWiFiClient.shared().interface(), let name = interface.interfaceName else { return nil }
            return WiFiLink(name: name, powered: interface.powerOn(), rate: interface.transmitRate(), rssi: interface.rssiValue())
        }
        guard let cached else {
            previousNetwork = nil
            return nil
        }
        let (name, powered, rate, rssi) = (cached.name, cached.powered, cached.rate, cached.rssi)
        var received: Double?
        var sent: Double?
        var addresses: UnsafeMutablePointer<ifaddrs>?
        if powered && rate > 0 && getifaddrs(&addresses) == 0 {
            defer { freeifaddrs(addresses) }
            var current = addresses
            while let entry = current {
                defer { current = entry.pointee.ifa_next }
                guard String(cString: entry.pointee.ifa_name) == name,
                      entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                      let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                let now = ProcessInfo.processInfo.systemUptime
                let input = data.pointee.ifi_ibytes
                let output = data.pointee.ifi_obytes
                if let previousNetwork, previousNetwork.name == name, now > previousNetwork.time {
                    received = Double(input &- previousNetwork.received) / (now - previousNetwork.time)
                    sent = Double(output &- previousNetwork.sent) / (now - previousNetwork.time)
                }
                previousNetwork = (name, input, output, now)
                break
            }
        } else { previousNetwork = nil }
        return .init(interface: name, powered: powered, connected: powered && rate > 0,
                     linkRate: rate, received: received, sent: sent,
                     signalDBm: powered && rate > 0 && rssi != 0 ? rssi : nil)
    }
}
