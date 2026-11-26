import Foundation

/// Une application installée, repérée par son bundle et son identifiant.
struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleId: String?

    var id: String { url.path }
}

/// Recense les applications installées dans /Applications et ~/Applications.
enum AppCatalog {
    static var applicationDirectories: [String] {
        ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
    }
    static func isProtectedApplication(_ url: URL) -> Bool {
        let id = Bundle(url: url)?.bundleIdentifier
        if let id, id == Bundle.main.bundleIdentifier || id == "org.maccare.app" { return true }
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_RESTRICTED) != 0
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
                if isProtectedApplication(url) { continue }
                apps.append(AppInfo(url: url, name: name, bundleId: bundleId))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
