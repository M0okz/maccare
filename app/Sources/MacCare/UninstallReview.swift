import AppKit

enum UninstallDataUse: Equatable {
    case application, exclusive, container, personal, nameOnly, machine, group, declaredGroup, shared(String)

    var preselected: Bool { self == .application || self == .exclusive || self == .container }
    var canRemove: Bool {
        switch self {
        case .group, .shared: return false
        default: return true
        }
    }

    var reason: String {
        switch self {
        case .application: return "Copie de l’application à cet emplacement."
        case .exclusive: return "Fichier propre à l’application ou à l’un de ses assistants."
        case .container: return "Conteneur de l’application ou de son assistant, y compris les documents qu’il contient."
        case .personal: return "Peut contenir un profil, des sessions ou des documents personnels."
        case .nameOnly: return "Trouvé par le nom de l’application. Vérifiez son contenu avant de le retirer."
        case .machine: return "Composant installé pour tous les utilisateurs de ce Mac."
        case .declaredGroup: return "Groupe déclaré par l’application. Le retirer efface aussi les données de ses extensions."
        case .group: return "Les applications qui utilisent ce groupe n’ont pas pu être identifiées."
        case .shared(let copy): return "Conservé pour l’autre application située dans \(copy)."
        }
    }
}

struct UninstallReview {
    private(set) var candidates: [String: UninstallDataUse] = [:]

    private static let browserProfiles = [
        "com.google.chrome": "Google/Chrome", "com.google.chrome.beta": "Google/Chrome Beta",
        "com.google.chrome.canary": "Google/Chrome Canary", "com.brave.browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge", "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox", "org.mozilla.nightly": "Firefox"
    ]

    init(app: AppInfo, others: [AppInfo], groupIDs: [String] = [], embeddedIDs: Set<String> = [],
         otherClaims: [String: AppInfo] = [:],
         library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
         darwinDirectories: [URL] = [], machineLibrary: URL? = nil) {
        let id = app.bundleId?.lowercased()
        let copy = others.first { id != nil && $0.bundleId?.lowercased() == id }
        let sameName = others.first { $0.name.caseInsensitiveCompare(app.name) == .orderedSame }
        func relative(_ path: String) -> String { library.appendingPathComponent(path).standardizedFileURL.path }
        func sharing(_ owner: AppInfo?, otherwise use: UninstallDataUse) -> UninstallDataUse {
            owner.map { .shared($0.url.path) } ?? use
        }

        if Self.validComponent(app.name) {
            for directory in ["Application Support", "Logs", "Caches", "Preferences"] {
                candidates[relative("\(directory)/\(app.name)")] = sharing(copy ?? sameName, otherwise: .nameOnly)
            }
        }
        if let bid = app.bundleId, UninstallArtifacts.validID(bid) {
            let hostPreferences = (try? FileManager.default.contentsOfDirectory(
                atPath: library.appendingPathComponent("Preferences/ByHost").path)) ?? []
            let ids = embeddedIDs.union([bid]).union(UninstallArtifacts.legacyLoginIDs(for: bid))
            for identifier in ids where UninstallArtifacts.validID(identifier) {
                let owner = copy ?? otherClaims[identifier.lowercased()]
                for path in ["Caches/\(identifier)", "Caches/\(identifier).plist", "Preferences/\(identifier).plist",
                             "Preferences/\(identifier)", "Saved Application State/\(identifier).savedState",
                             "Logs/\(identifier)", "LaunchAgents/\(identifier).plist", "Application Scripts/\(identifier)"] {
                    candidates[relative(path)] = sharing(owner, otherwise: .exclusive)
                }
                candidates[relative("Containers/\(identifier)")] = sharing(owner, otherwise: .container)
                for path in ["Application Support/\(identifier)", "HTTPStorages/\(identifier)",
                             "HTTPStorages/\(identifier).binarycookies", "WebKit/\(identifier)", "Cookies/\(identifier).binarycookies"] {
                    candidates[relative(path)] = sharing(owner, otherwise: .personal)
                }
                for root in darwinDirectories {
                    candidates[root.appendingPathComponent(identifier).path] = sharing(owner, otherwise: .exclusive)
                    // Processus WebKit lancés pour le compte de l’app : leur cache porte son identifiant.
                    for process in Self.webKitProcesses {
                        candidates[root.appendingPathComponent("\(process)+\(identifier)").path] = sharing(owner, otherwise: .exclusive)
                    }
                }
                for name in hostPreferences where Self.isHostPreference(name, of: identifier) {
                    candidates[relative("Preferences/ByHost/\(name)")] = sharing(owner, otherwise: .exclusive)
                }
                for ext in ["sfl", "sfl2", "sfl3", "sfl4"] {
                    let recents = "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"
                    candidates[relative("\(recents)/\(identifier.lowercased()).\(ext)")] = sharing(owner, otherwise: .exclusive)
                }
            }
            candidates[relative("Group Containers/\(bid)")] = .group
            for group in groupIDs where Self.validComponent(group) {
                let use = sharing(copy ?? otherClaims[group.lowercased()], otherwise: .declaredGroup)
                candidates[relative("Group Containers/\(group)")] = use
                candidates[relative("Application Scripts/\(group)")] = use
            }
            if let profile = Self.browserProfiles[bid.lowercased()] {
                let owner = others.first { Self.browserProfiles[$0.bundleId?.lowercased() ?? ""] == profile }
                candidates[relative("Application Support/\(profile)")] = sharing(owner ?? copy ?? sameName, otherwise: .personal)
            }
            if let machineLibrary {
                for url in UninstallArtifacts.machineItems(app: app, library: machineLibrary) {
                    candidates[url.path] = sharing(copy ?? sameName, otherwise: .machine)
                }
            }
        }
        candidates[app.url.standardizedFileURL.path] = .application
    }

    func use(of item: ScanItem) -> UninstallDataUse? { candidates[item.path] ?? candidates[item.url.standardizedFileURL.path] }

    static func current(for app: AppInfo, artifacts supplied: UninstallArtifacts? = nil) -> Self {
        let artifacts = supplied ?? UninstallArtifacts(app: app)
        var apps = AppCatalog.installedApps()
        var identifiers = artifacts.embeddedIDs
        if let id = app.bundleId {
            identifiers.insert(id)
            identifiers.formUnion(UninstallArtifacts.legacyLoginIDs(for: id))
            if let profile = browserProfiles[id.lowercased()] {
                identifiers.formUnion(browserProfiles.compactMap { $0.value == profile ? $0.key : nil })
            }
        }
        for id in identifiers {
            let registered = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).compactMap(\.bundleURL)
            for url in Set(registered + running) where FileManager.default.fileExists(atPath: url.path) {
                guard let actual = Bundle(url: url)?.bundleIdentifier,
                      actual.caseInsensitiveCompare(id) == .orderedSame else { continue }
                apps.append(AppInfo(url: url, name: url.deletingPathExtension().lastPathComponent, bundleId: actual))
            }
        }
        let target = app.url.resolvingSymlinksInPath().standardizedFileURL.path
        var seen = Set<String>()
        let others = apps.filter {
            let url = $0.url.resolvingSymlinksInPath().standardizedFileURL
            return url.path != target && !url.path.hasPrefix(target + "/") && seen.insert(url.path).inserted
                && !url.pathComponents.contains(".Trash") && !url.pathComponents.contains(".Trashes")
        }
        var claims = [String: AppInfo]()
        for other in others {
            if let id = other.bundleId { claims[id.lowercased()] = other }
            if !artifacts.groups.isEmpty || !artifacts.embeddedIDs.isEmpty {
                let metadata = UninstallArtifacts(app: other)
                for id in metadata.groups.union(metadata.embeddedIDs) { claims[id.lowercased()] = other }
            }
        }
        return Self(app: app, others: others, groupIDs: Array(artifacts.groups), embeddedIDs: artifacts.embeddedIDs,
                    otherClaims: claims, darwinDirectories: UninstallArtifacts.darwinDirectories,
                    machineLibrary: URL(fileURLWithPath: "/Library"))
    }

    static let webKitProcesses = ["com.apple.WebKit.GPU", "com.apple.WebKit.Networking", "com.apple.WebKit.WebContent",
                                  "com.apple.WebKit.WebContent.EnhancedSecurity"]

    /// `<identifiant>.<UUID matériel>.plist` : le segment hôte ne contient ni point ni autre signe.
    static func isHostPreference(_ name: String, of identifier: String) -> Bool {
        let prefix = identifier.lowercased() + ".", lower = name.lowercased()
        guard lower.hasPrefix(prefix), lower.hasSuffix(".plist") else { return false }
        let host = lower.dropFirst(prefix.count).dropLast(".plist".count)
        return host.count >= 12 && host.allSatisfy { $0 == "-" || $0.isHexDigit }
    }

    static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }
}
