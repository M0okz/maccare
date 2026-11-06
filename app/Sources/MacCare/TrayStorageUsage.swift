import Foundation

/// Le disponible macOS peut inclure de l’espace purgeable ; ce n’est pas une analyse de fichiers.
struct TrayStorageUsage {
    let available: UInt64
    let total: UInt64
    var used: UInt64 { total - available }
    var fraction: Double { Double(used) / Double(total) }
    var percent: Int { Int((fraction * 100).rounded()) }

    init?(free: UInt64, total: UInt64) {
        guard total > 0 else { return nil }
        self.total = total
        available = min(free, total)
    }
}
