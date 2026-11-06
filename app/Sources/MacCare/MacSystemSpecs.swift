import Foundation
import Darwin

enum MacSystemSpecs {
    static let ram = "\((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1)))) Go RAM"
    static let systemVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }()
    static let bootDate: Date? = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(boot.tv_sec))
    }()
    static func uptime(now: Date = Date()) -> String {
        guard let bootDate else { return "Durée indisponible" }
        return "Actif depuis \(duration(now.timeIntervalSince(bootDate)))"
    }
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "moins d’une minute" }
        let days = minutes / 1440, hours = (minutes / 60) % 24
        if days > 0 { return "\(days) j \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes % 60) min" }
        return "\(minutes) min"
    }
}
