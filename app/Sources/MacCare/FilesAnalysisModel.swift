import Combine
import AppKit

@MainActor
final class FilesAnalysisModel: ObservableObject {
    @Published private(set) var hasStarted = false
    @Published private(set) var requestedLarge = false
    @Published private(set) var requestedDuplicates = false
    @Published var browsing = false
    @Published var choosingLocation = false
    @Published private(set) var searchRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    @Published var locationError: String?

    func setRoot(_ url: URL) {
        guard FileSearchScope.isAllowed(url) else {
            locationError = "Choisissez un dossier dans votre dossier personnel, hors Bibliothèque, dossiers cachés et paquets."
            return
        }
        searchRoot = url.standardizedFileURL.resolvingSymlinksInPath()
        locationError = nil
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = searchRoot
        panel.prompt = "Choisir ce dossier"
        panel.message = "Choisissez un dossier personnel à analyser. Aucun fichier ne sera supprimé pendant l’analyse."
        panel.canCreateDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.setRoot(url) }
        }
    }

    func analyze(large: LargeFilesModel, duplicates: DuplicatesModel, preferences: FileStoragePreferences = FileStoragePreferences()) {
        guard large.stage != .scanning, duplicates.stage != .scanning, !large.isTrashing, !duplicates.isTrashing else { return }
        guard preferences.hasSearch else { return }
        requestedLarge = preferences.searchLarge
        requestedDuplicates = preferences.searchDuplicates
        choosingLocation = false
        hasStarted = true
        browsing = false
        if requestedLarge {
            large.applyDefaultFilters(preferences)
            large.scan(at: searchRoot)
        }
        if requestedDuplicates { duplicates.scan(at: searchRoot) }
    }

    func cancel(large: LargeFilesModel, duplicates: DuplicatesModel) {
        if requestedLarge { large.cancel() }
        if requestedDuplicates { duplicates.cancel() }
    }
}

/// Le moteur reste l’autorité finale ; ce contrôle donne un retour immédiat dans le sélecteur.
enum FileSearchScope {
    static func isAllowed(_ url: URL, home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = home.standardizedFileURL.resolvingSymlinksInPath().path
        guard path == base || path.hasPrefix(base + "/") else { return false }
        let components = path == base ? [] : String(path.dropFirst(base.count + 1)).split(separator: "/").map(String.init)
        if components.first == "Library" { return false }
        return !components.contains { $0.hasPrefix(".") || ["app", "bundle", "photoslibrary", "photolibrary"].contains(($0 as NSString).pathExtension.lowercased()) }
    }
}
