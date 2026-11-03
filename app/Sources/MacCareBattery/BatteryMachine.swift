import Foundation
import IOKit
import CryptoKit

/// Local-only host binding for recovery across crashes/reboots. Never included in XPC status/logs.
enum BatteryMachine {
    static let identity: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              let uuid = UUID(uuidString: value) else { return nil }
        return SHA256.hash(data: Data(uuid.uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
    }()
}
