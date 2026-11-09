import Foundation

/// Mise à la corbeille (ou suppression, si demandé) d'une sélection, validée par le moteur.
///
/// Le moteur re-vérifie chaque élément (confinement au périmètre, chemins protégés, identité
/// device+inode inchangée depuis le scan, liens symboliques) avant que l'app y touche : seuls les
/// chemins qu'il autorise sont déplacés. À appeler hors du thread principal.
enum Remover {
    static func remove(_ items: [ScanItem], scopeRoot: String, direct: Bool, rule: String? = nil) throws -> RemovalReport {
        var report = RemovalReport(direct: direct)
        let input = PlanInput(
            scope_root: scopeRoot,
            items: items.map { PlanItem(path: $0.path, identity: $0.identity) }, rule: rule
        )
        if direct {
            for r in try Engine.executeRemoval(input) {
                if r.removed { report.removed += 1 }
                else if !r.allowed { report.refused.append((r.path, r.refusal ?? "refusé")) }
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
                } catch {
                    report.failed.append((item.path, error.localizedDescription))
                }
            }
        }
        return report
    }

    /// Le paquet choisi et ses données appartiennent à deux périmètres distincts.
    /// La liste d’inclusion n’est utilisée que pour le chemin exact du paquet choisi.
    static func uninstall(_ items: [ScanItem], app: AppInfo, direct: Bool) throws -> RemovalReport {
        let bundleURL = app.url.standardizedFileURL
        let bundle = items.filter { $0.url.standardizedFileURL == bundleURL }
        let data = items.filter { $0.url.standardizedFileURL != bundleURL }
        var report = RemovalReport(direct: direct)
        if !bundle.isEmpty {
            let root = bundleURL.deletingLastPathComponent().path
            guard app.url.pathExtension == "app", AppCatalog.applicationDirectories.contains(root) else {
                throw Engine.EngineError.engine("L’application choisie n’est pas dans un dossier Applications.")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            func quoted(_ value: String) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
            let rule = """
            id = "uninstall.selected-application"
            category = "uninstall"
            version = 1
            root = \(try quoted(root))
            depth = "per-app"
            [[include]]
            kind = "name-suffix"
            ends_with = \(try quoted(bundleURL.lastPathComponent))
            """
            report = try remove(bundle, scopeRoot: root, direct: direct, rule: rule)
        }
        if !data.isEmpty {
            let result = try remove(data, scopeRoot: NSHomeDirectory(), direct: direct)
            report.removed += result.removed
            report.refused += result.refused
            report.failed += result.failed
        }
        return report
    }
}
