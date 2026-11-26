import AppKit

/// Un instantané des applications en cours pour chaque retrait. Seules les métadonnées
/// stables des processus sont réutilisées pendant l’opération.
struct RunningCacheApplications {
    typealias Lookup = (ScanItem, String) -> [String]

    static func liveLookup() -> Lookup {
        var applications = Self()
        return { applications.blockingNames(for: $0, root: $1) }
    }

    private struct Owner {
        let name: String
        let identifiers: Set<String>
        let folderNames: Set<String>
        let bundles: Set<URL>

        init(_ app: NSRunningApplication) {
            let parent = app.bundleURL.flatMap { TrayProcessIconResolver.owningApplication(in: $0.path) }
            let urls = Set([parent, app.bundleURL].compactMap { $0 })
            let bundles = urls.compactMap(Bundle.init(url:))
            let ids = [app.bundleIdentifier].compactMap { $0 } + bundles.compactMap(\.bundleIdentifier)
            identifiers = Set(ids.map { $0.lowercased() })
            self.bundles = urls
            let parentName = parent?.deletingPathExtension().lastPathComponent
            name = parentName ?? app.localizedName ?? app.bundleIdentifier ?? "Application"
            var names = [name, app.localizedName].compactMap { $0 } + urls.map { $0.deletingPathExtension().lastPathComponent }
            names += bundles.compactMap { $0.object(forInfoDictionaryKey: "CFBundleName") as? String }
            // Certains caches ont un nom de produit ou un dossier éditeur commun aux canaux.
            for id in identifiers {
                if id.hasPrefix("org.mozilla.firefox") || id == "org.mozilla.nightly" { names.append("Firefox") }
                if id == "com.google.chrome" || id.hasPrefix("com.google.chrome.") { names.append("Google") }
                if id == "com.brave.browser" || id.hasPrefix("com.brave.browser.") { names.append("BraveSoftware") }
                if id == "com.microsoft.vscode" { names.append("Code") }
                if id == "com.microsoft.vscodeinsiders" { names.append("Code - Insiders") }
            }
            folderNames = Set(names.map { $0.lowercased() })
        }
    }

    private var owners: [NSRunningApplication: Owner] = [:]
    private var groups: [URL: Set<String>] = [:]

    static func matchesBundle(_ cache: String, runningID: String) -> Bool {
        cache == runningID || runningID.hasPrefix(cache + ".") || cache.hasPrefix(runningID + ".")
    }

    static func isApplicationCache(_ category: String) -> Bool {
        ["user-cache", "container-cache", "group-container-cache", "electron-cache", "xcode-documentation-cache"].contains(category)
    }

    static func containerIdentifier(_ folder: String, root: String) -> String? {
        guard UUID(uuidString: folder) != nil else { return nil }
        let metadata = URL(fileURLWithPath: root).appendingPathComponent(folder)
            .appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let data = try? Data(contentsOf: metadata),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    mutating func blockingNames(for item: ScanItem, root: String) -> [String] {
        let folder = item.owner ?? item.url.lastPathComponent
        var key = folder.lowercased()
        if item.category == "xcode-documentation-cache" { key = "com.apple.dt.xcode" }
        if ["container-cache", "group-container-cache"].contains(item.category),
           let identifier = Self.containerIdentifier(folder, root: root) { key = identifier.lowercased() }
        let profile = SmartScanAppProfile.knownOwner(key)
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            let owner = owners[app] ?? Owner(app)
            owners[app] = owner
            if owner.folderNames.contains(key) || owner.identifiers.contains(where: { Self.matchesBundle(key, runningID: $0) })
                || (profile != nil && owner.identifiers.contains { SmartScanAppProfile.knownOwner($0) == profile }) {
                names.insert(owner.name)
            } else if item.category == "group-container-cache" {
                for url in owner.bundles {
                    let declared = groups[url] ?? Set(ApplicationGroups.declared(at: url).map { $0.lowercased() })
                    groups[url] = declared
                    if declared.contains(key) { names.insert(owner.name); break }
                }
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
