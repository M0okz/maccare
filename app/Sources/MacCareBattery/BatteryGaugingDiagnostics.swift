import Foundation
import CoreFoundation

/// A bounded, read-only snapshot of powerd's recorded tracking data. These dates
/// are evidence, never authority to enable charging controls or reset Apple state.
public struct BatteryGaugingDiagnostics: Codable, Sendable {
    public enum ReadState: String, Codable, Sendable { case available, unavailable, invalidFormat, tooLarge }
    public struct Pack: Codable, Sendable {
        public let lastDOD0Update: String?
        public let lastQMaxUpdate: String?
        public let lastQualQMaxDate: String?
    }
    public let readState: ReadState
    public let lastChargeToFullCheckDate: String?
    public let lastFullChargeDate: String?
    public let lastFullChargeReq: Bool?
    /// Anonymous values only: the source dictionary's keys can contain serial numbers.
    public let packs: [Pack]
    static let maximumBytes = 65_536

    public static func read() -> Self {
        let url = URL(fileURLWithPath: "/private/var/root/Library/Preferences/com.apple.powerd.batterygauging.plist")
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return parse(try handle.read(upToCount: maximumBytes + 1) ?? Data())
        } catch { return empty(.unavailable) }
    }

    static func parse(_ data: Data) -> Self {
        guard data.count <= maximumBytes else { return empty(.tooLarge) }
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let info = root["batteryGaugingMitigationInfo"] as? [String: Any],
              let packData = info["batteryPackData"] as? [String: Any], packData.count <= 16 else {
            return empty(.invalidFormat)
        }
        let formatter = ISO8601DateFormatter()
        func date(_ dictionary: [String: Any], _ key: String) throws -> String? {
            guard let value = dictionary[key] else { return nil }
            guard let date = value as? Date else { throw CocoaError(.coderInvalidValue) }
            return formatter.string(from: date)
        }
        do {
            let request: Bool?
            if let value = info["lastFullChargeReq"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    return empty(.invalidFormat)
                }
                request = number.boolValue
            } else { request = nil }
            var packs: [Pack] = []
            for value in packData.values {
                guard let pack = value as? [String: Any] else { return empty(.invalidFormat) }
                packs.append(try .init(lastDOD0Update: date(pack, "lastDOD0Update"),
                                       lastQMaxUpdate: date(pack, "lastQMaxUpdate"),
                                       lastQualQMaxDate: date(pack, "lastQualQMaxDate")))
            }
            // Stable output without sorting or exposing serial-number keys.
            packs.sort {
                [$0.lastDOD0Update ?? "", $0.lastQMaxUpdate ?? "", $0.lastQualQMaxDate ?? ""]
                    .lexicographicallyPrecedes([$1.lastDOD0Update ?? "", $1.lastQMaxUpdate ?? "", $1.lastQualQMaxDate ?? ""])
            }
            return try .init(readState: .available, lastChargeToFullCheckDate: date(info, "lastChargeToFullCheckDate"),
                             lastFullChargeDate: date(info, "lastFullChargeDate"), lastFullChargeReq: request, packs: packs)
        } catch { return empty(.invalidFormat) }
    }

    private static func empty(_ state: ReadState) -> Self {
        .init(readState: state, lastChargeToFullCheckDate: nil, lastFullChargeDate: nil, lastFullChargeReq: nil, packs: [])
    }
}
