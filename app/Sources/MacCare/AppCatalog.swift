import Foundation

/// Une application installée, repérée par son bundle et son identifiant.
struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleId: String?

    var id: String { url.path }

    /// Chemins de résidus candidats pour cette app. Rien n'est vérifié ici : le moteur
    /// (`inspectPaths`) ne gardera que ceux qui existent réellement.
    var residualCandidates: [String] {
        let lib = (NSHomeDirectory() as NSString).appendingPathComponent("Library")
        func L(_ parts: String...) -> String {
            parts.reduce(lib) { ($0 as NSString).appendingPathComponent($1) }
        }

        var paths: [String] = []

        if let b = bundleId, !b.isEmpty {
            paths += [
                L("Caches", b),
                L("Preferences", "\(b).plist"),
                L("Preferences", b),                       // certains apps créent un dossier
                L("Containers", b),
                L("Group Containers", b),
                L("Application Support", b),
                L("Application Scripts", b),
                L("Saved Application State", "\(b).savedState"),
                L("HTTPStorages", b),
                L("HTTPStorages", "\(b).binarycookies"),
                L("WebKit", b),
                L("Logs", b),
                L("LaunchAgents", "\(b).plist"),
                L("Cookies", "\(b).binarycookies"),
                L("Caches", "\(b).plist"),
            ]
        }

        paths += [
            L("Application Support", name),
            L("Logs", name),
            L("Caches", name),
            L("Preferences", name),
        ]

        // Le paquet choisi est retiré dans son propre périmètre Applications.
        paths.append(url.path)

        // Déduplique en conservant l'ordre.
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

/// Recense les applications installées dans /Applications et ~/Applications.
enum AppCatalog {
    static var applicationDirectories: [String] {
        ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
    }
    static func installedApps() -> [AppInfo] {
        let fm = FileManager.default
        var apps: [AppInfo] = []

        for dir in applicationDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let name = (entry as NSString).deletingPathExtension
                let bundleId = Bundle(url: url)?.bundleIdentifier
                // MacCare cannot remove itself: its running helper must be deactivated first.
                if bundleId == Bundle.main.bundleIdentifier { continue }
                apps.append(AppInfo(url: url, name: name, bundleId: bundleId))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
