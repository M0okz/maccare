import Foundation

/// Occupation fournie par macOS, distincte de la somme partielle des fichiers mesurés.
struct SpaceVolumeUsage {
    let name: String
    let total: UInt64
    let used: UInt64

    static func read(at path: String) -> Self? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        guard let free = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else { return nil }
        return Self(name: values.volumeName ?? "Volume", total: UInt64(total), used: UInt64(max(0, Int64(total) - free)))
    }
}
