import SwiftUI

struct FileStorageSettingsView: View {
    @AppStorage(FileStoragePreferences.Key.large) private var searchLarge = true
    @AppStorage(FileStoragePreferences.Key.duplicates) private var searchDuplicates = true
    @AppStorage(FileStoragePreferences.Key.minSize) private var minSize = Int(LargeFilesModel.MinSize.mb100.rawValue)
    @AppStorage(FileStoragePreferences.Key.age) private var age = LargeFilesModel.Age.any.rawValue
    @AppStorage(FileStoragePreferences.Key.view) private var view = SpaceDisplayMode.map.rawValue
    @AppStorage(FileStoragePreferences.Key.start) private var start = SpaceStartFolder.startupDisk.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("Mes fichiers") {
                Toggle("Rechercher les gros fichiers", isOn: $searchLarge)
                Toggle("Rechercher les doublons", isOn: $searchDuplicates)
                inlineHelp(title: "À propos des recherches", message: "La comparaison des doublons peut prendre plus de temps. Ces choix s’appliquent à la prochaine analyse de Mes fichiers.")
                if !searchLarge && !searchDuplicates {
                    Label("Activez au moins une recherche pour lancer une analyse.", systemImage: "info.circle")
                        .foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            group("Filtres initiaux des gros fichiers") {
                settingRow("Taille minimale") {
                    Picker("Taille minimale", selection: $minSize) {
                        ForEach(LargeFilesModel.MinSize.allCases) { Text($0.title).tag(Int($0.rawValue)) }
                    }.labelsHidden().accessibilityLabel("Taille minimale")
                }
                settingRow("Dernière ouverture") {
                    Picker("Dernière ouverture", selection: $age) {
                        ForEach(LargeFilesModel.Age.allCases) { Text($0.title).tag($0.rawValue) }
                    }.labelsHidden().accessibilityLabel("Dernière ouverture")
                }
                inlineHelp(title: "À propos des filtres", message: "Vous pourrez ajuster ces filtres dans les résultats. Un fichier ancien ou volumineux n’est pas forcément inutile.")
            }
            group("Espace disque") {
                settingRow("Vue de l’explorateur") {
                    Picker("Vue de l’explorateur", selection: $view) {
                        ForEach(SpaceDisplayMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }.labelsHidden().accessibilityLabel("Vue de l’explorateur")
                }

                settingRow("Point de départ") {
                    Picker("Point de départ", selection: $start) {
                        ForEach(SpaceStartFolder.allCases) { Text($0.title).tag($0.rawValue) }
                    }.labelsHidden().accessibilityLabel("Point de départ")
                }
                inlineHelp(title: "À propos de l’explorateur", message: "Ces choix sont mémorisés. Le point de départ s’applique au prochain lancement. Vous pouvez choisir un volume ou un dossier dans Espace disque. En vue Carte, la liste reste visible à côté lorsque la fenêtre est assez large.")
            }
            inlineHelp(title: "Périmètre des recherches", message: "Mes fichiers recherche dans le dossier personnel ou le sous-dossier choisi avant l’analyse. La recherche de doublons exclut notamment les projets de code et la bibliothèque utilisateur. Les fichiers choisis passent toujours par la corbeille.")
        }
        .font(AppFont.secondary)
    }

    private func inlineHelp(title: String, message: String) -> some View {
        Text(message).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 170, alignment: .leading)
            content().frame(maxWidth: .infinity)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
