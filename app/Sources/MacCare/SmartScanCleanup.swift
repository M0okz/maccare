import Foundation

struct DeferredCache {
    let item: ScanItem
    let apps: [String]
    let direct: Bool
}

struct SmartScanCleanup {
    var report: RemovalReport
    var removedPaths: Set<String> = []
    var measuredBytes: UInt64 = 0
    var waiting: [DeferredCache]

    struct AppTotal: Identifiable {
        let id: String
        let bytes: UInt64
    }

    var appTotals: [AppTotal] {
        Dictionary(grouping: waiting, by: { $0.apps.joined(separator: ", ") }).map { name, caches in
            AppTotal(id: name, bytes: caches.reduce(0) { $0 + $1.item.size_bytes })
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    mutating func remove(_ items: [ScanItem], category: CleaningCategory, rule: String) {
        do {
            var paths = Set<String>()
            let result = try Remover.remove(items, scopeRoot: category.root, direct: report.direct, rule: rule) {
                paths.insert($0)
            }
            for item in items where paths.contains(item.path) && removedPaths.insert(item.path).inserted {
                measuredBytes += item.size_bytes
            }
            report.removed += result.removed
            report.refused += result.refused
            report.failed += result.failed
        } catch {
            report.failed += items.map { ($0.path, error.localizedDescription) }
        }
    }
}
