import AppKit
import Foundation
import MacCareMaintenance

struct PurgeableCachePlan {
    let items: [ScanItem]
    let rule: String
    let root: String
    let createdAt: Date
    var bytes: UInt64 { items.reduce(0) { $0 + $1.size_bytes } }
}

/// Périmètre explicite de caches utilisateur ; aucune commande Time Machine/APFS.
enum PurgeableCacheService {
    @MainActor static func closedApplicationIDs() -> Set<String> {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return Set(names.filter { name in
            !name.hasPrefix("com.apple.") &&
            !running.contains(where: { $0 == name || $0.hasPrefix(name + ".") }) &&
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) != nil
        })
    }

    static func prepare(allowedIDs: Set<String>, exclusions: [String]) throws -> PurgeableCachePlan {
        guard let category = CleaningCategory.all.first(where: { $0.id == "cache.generic" }),
              category.risk == .safe else { throw Engine.EngineError.engine("Règle de caches indisponible.") }
        let rule = category.ruleTOML(thresholdBytes: nil, userExclusions: exclusions)
        let items = try Engine.scan(ruleTOML: rule).filter { item in
            let url = URL(fileURLWithPath: item.path)
            return url.deletingLastPathComponent().path == category.root &&
                allowedIDs.contains(url.lastPathComponent) && item.size_bytes > 0
        }
        return PurgeableCachePlan(items: items, rule: rule, root: category.root, createdAt: Date())
    }

    static func execute(_ plan: PurgeableCachePlan, allowedIDs: Set<String>) -> MaintenanceReport {
        guard Date().timeIntervalSince(plan.createdAt) < 15 * 60 else {
            return .init(.failed, "Le bilan des caches a expiré. Actualisez-le avant de confirmer.")
        }
        var removed = 0
        var refused = 0
        var failures: [String] = []
        for item in plan.items {
            let bundleID = URL(fileURLWithPath: item.path).lastPathComponent
            guard allowedIDs.contains(bundleID),
                  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { refused += 1; continue }
            let input = PlanInput(scope_root: plan.root,
                                  items: [PlanItem(path: item.path, identity: item.identity)], rule: plan.rule)
            do {
                let results = try Engine.executeRemoval(input)
                removed += results.filter(\.removed).count
                refused += results.filter { !$0.allowed }.count
                failures += results.compactMap(\.error)
                if results.isEmpty { failures.append("Aucun résultat renvoyé par le moteur.") }
            } catch { failures.append(error.localizedDescription) }
        }
        let incomplete = refused > 0 || !failures.isEmpty
        return .init(incomplete ? (removed > 0 ? .partial : .failed) : .completed,
                     "\(removed) dossier(s) de cache supprimé(s)\(incomplete ? " · certains éléments n’ont pas été traités" : ""). Cette étape ne modifie pas les instantanés.",
                     details: "\(refused) élément(s) refusé(s). L’espace physique libéré dépend du système de fichiers.\n" + failures.joined(separator: "\n"))
    }
}
