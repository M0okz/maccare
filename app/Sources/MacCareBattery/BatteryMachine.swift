import Foundation
import IOKit
import CryptoKit

/// Local-only host binding for recovery across crashes/reboots. Never included in XPC status/logs.
enum BatteryMachine {
    /// Hardware model only, for the support allowlist. Identifies no individual machine.
    static let model: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size <= 64 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }()
    static let identity: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              let uuid = UUID(uuidString: value) else { return nil }
        return SHA256.hash(data: Data(uuid.uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
    }()
}
