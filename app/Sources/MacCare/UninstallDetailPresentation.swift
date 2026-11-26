import Foundation

/// Présentation de la sélection, sans modifier les candidats ni les gardes du moteur.
struct UninstallDetailPresentation {
    let app: AppInfo
    let items: [ScanItem]
    let selection: Set<String>
    let directDelete: Bool

    private func isApplication(_ item: ScanItem) -> Bool {
        item.url.standardizedFileURL.path == app.url.standardizedFileURL.path
    }

    var applicationItems: [ScanItem] { items.filter(isApplication) }
    var associatedItems: [ScanItem] { items.filter { !isApplication($0) } }
    var includesApplication: Bool { applicationItems.contains { selection.contains($0.id) } }
    var hasSelection: Bool { items.contains { selection.contains($0.id) } }
    /// Conteneurs cochés : macOS n’en autorise le retrait qu’avec l’Accès complet au disque.
    var selectedContainers: [ScanItem] {
        associatedItems.filter { selection.contains($0.id) && UninstallFileOperations.isAppContainer($0.url) }
    }

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
        // Sans paquet à cet emplacement, rien ne permet d’affirmer que l’application reste installée.
        let installed = applicationItems.isEmpty ? "" : "L’application reste installée. "
        return directDelete
            ? installed + "Les données cochées seront supprimées définitivement."
            : installed + "Les données cochées seront déplacées vers la corbeille."
    }
}
