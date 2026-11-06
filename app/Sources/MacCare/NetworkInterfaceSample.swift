import Foundation
import Darwin
import SystemConfiguration

/// Une seule interface de la route principale : IP et compteurs restent associés.
struct NetworkInterfaceSample: Sendable {
    let name: String
    let address: String?
    let kind: TrayMetrics.Network.Kind
    let received: UInt32
    let sent: UInt32

    static func primaryName(ipv4: [String: Any]?, ipv6: [String: Any]?) -> String? {
        for state in [ipv4, ipv6] {
            if let name = state?[kSCDynamicStorePropNetPrimaryInterface as String] as? String, !name.isEmpty { return name }
        }
        return nil
    }

    static func kind(name: String, type: String?, wifiName: String?) -> TrayMetrics.Network.Kind {
        if ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains(where: name.hasPrefix) { return .vpn }
        if name == wifiName || type == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if type == kSCNetworkInterfaceTypeEthernet as String { return .ethernet }
        return .other
    }

    static func interfaceTypes() -> [String: String] {
        var types: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            if let name = SCNetworkInterfaceGetBSDName(interface), let type = SCNetworkInterfaceGetInterfaceType(interface) {
                types[name as String] = type as String
            }
        }
        return types
    }

    static func current(types: [String: String], wifiName: String?) -> Self? {
        let ipv4 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let ipv6 = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
        guard let name = primaryName(ipv4: ipv4, ipv6: ipv6) else { return nil }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var current = addresses
        var ip4: String?, ip6: String?
        var counters: (UInt32, UInt32)?
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == name,
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = entry.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            if family == AF_LINK, let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                counters = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
            } else if family == AF_INET || family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if family == AF_INET { ip4 = ip }
                    else if !ip.lowercased().hasPrefix("fe80:") { ip6 = ip }
                }
            }
        }
        guard let counters else { return nil }
        return .init(name: name, address: ip4 ?? ip6, kind: kind(name: name, type: types[name], wifiName: wifiName),
                     received: counters.0, sent: counters.1)
    }
}
