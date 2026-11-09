import Foundation

/// Présentation de la sélection, sans modifier les candidats ni les gardes du moteur.
struct UninstallDetailPresentation {
    let app: AppInfo
    let items: [ScanItem]
    let selection: Set<String>
    let directDelete: Bool

    static func initialSelection(app: AppInfo, items: [ScanItem]) -> Set<String> {
        Set(items.map(\.id))
    }

    private func isApplication(_ item: ScanItem) -> Bool {
        item.url.standardizedFileURL.path == app.url.standardizedFileURL.path
    }

    var applicationItems: [ScanItem] { items.filter(isApplication) }
    var associatedItems: [ScanItem] { items.filter { !isApplication($0) } }
    var includesApplication: Bool { applicationItems.contains { selection.contains($0.id) } }
    var hasSelection: Bool { items.contains { selection.contains($0.id) } }

    var actionTitle: String {
        if includesApplication {
            return directDelete ? "Désinstaller \(app.name) définitivement" : "Désinstaller \(app.name)"
        }
        return directDelete ? "Supprimer les données définitivement" : "Mettre les données à la corbeille"
    }

    var consequence: String {
        guard hasSelection else { return "Sélectionnez les éléments à retirer." }
        if includesApplication {
            if !associatedItems.contains(where: { selection.contains($0.id) }) {
                return directDelete
                    ? "L’application sera supprimée définitivement. Les données associées seront conservées."
                    : "L’application sera déplacée vers la corbeille. Les données associées seront conservées."
            }
            return directDelete
                ? "L’application et les données cochées seront supprimées définitivement."
                : "L’application et les données cochées seront déplacées vers la corbeille."
        }
        return directDelete
            ? "L’application reste installée. Les données cochées seront supprimées définitivement."
            : "L’application reste installée. Les données cochées seront déplacées vers la corbeille."
    }
}
