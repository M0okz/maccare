import Foundation

/// Mise à la corbeille (ou suppression, si demandé) d'une sélection, validée par le moteur.
///
/// Le moteur re-vérifie chaque élément (confinement au périmètre, chemins protégés, identité
/// device+inode inchangée depuis le scan, liens symboliques) avant que l'app y touche : seuls les
/// chemins qu'il autorise sont déplacés. À appeler hors du thread principal.
enum Remover {
    static func remove(_ items: [ScanItem], scopeRoot: String, direct: Bool, rule: String? = nil,
                       didRemove: (String) -> Void = { _ in }) throws -> RemovalReport {
        var report = RemovalReport(direct: direct)
        let input = PlanInput(
            scope_root: scopeRoot,
            items: items.map { PlanItem(path: $0.path, identity: $0.identity) }, rule: rule
        )
        if direct {
            for r in try Engine.executeRemoval(input) {
                if r.removed {
                    report.removed += 1
                    didRemove(r.path)
                } else if !r.allowed { report.refused.append((r.path, r.refusal ?? "refusé")) }
                else if let e = r.error { report.failed.append((r.path, e)) }
            }
        } else {
            let decisions = try Engine.planRemoval(input)
            let allowed = Set(decisions.filter(\.allowed).map(\.path))
            for d in decisions where !d.allowed {
                report.refused.append((d.path, d.refusal ?? "refusé"))
            }
            for item in items where allowed.contains(item.path) {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    report.removed += 1
                    didRemove(item.path)
                } catch where UninstallFileOperations.isAccessDenial(error)
                    && access(item.url.deletingLastPathComponent().path, W_OK | X_OK) == 0 {
                    // Dossier inscriptible : le refus vient de la confidentialité de macOS, pas des droits.
                    report.failed.append((item.path, UninstallFileOperations.protectionMessage(
                        for: item.url, fullDisk: FullDiskAccess.state())))
                } catch {
                    report.failed.append((item.path, error.localizedDescription))
                }
            }
        }
        return report
    }
}
