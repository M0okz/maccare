import AppKit
import Security

/// La même décision alimente la case affichée et le contrôle précédant le retrait.
enum UninstallDataUse: Equatable {
    case application, exclusive, personal, nameOnly, group, shared(String)

    var preselected: Bool { self == .application || self == .exclusive }
    var canRemove: Bool {
        switch self {
        case .group, .shared: return false
        default: return true
        }
    }

    var reason: String {
        switch self {
        case .application: return "Copie de l’application à cet emplacement."
        case .exclusive: return "Fichier associé à l’identifiant de cette application."
        case .personal: return "Peut contenir un profil, des sessions ou des documents personnels."
        case .nameOnly: return "Trouvé par le nom de l’application. Vérifiez son contenu avant de le retirer."
        case .group: return "Conteneur de groupe conservé pour les apps et extensions qui peuvent le partager."
        case .shared(let copy): return "Conservé pour l’autre application située dans \(copy)."
        }
    }
}

struct UninstallReview {
    private(set) var candidates: [String: UninstallDataUse] = [:]

    // Ces navigateurs conservent leur profil sous un nom différent de leur paquet.
    private static let browserProfiles = [
        "com.google.chrome": "Google/Chrome", "com.google.chrome.beta": "Google/Chrome Beta",
        "com.google.chrome.canary": "Google/Chrome Canary", "com.brave.browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge", "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox", "org.mozilla.nightly": "Firefox"
    ]

    init(app: AppInfo, others: [AppInfo], groupIDs: [String] = [],
         library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) {
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
        if let bid = app.bundleId, Self.validComponent(bid) {
            for path in ["Caches/\(bid)", "Caches/\(bid).plist", "Preferences/\(bid).plist",
                         "Preferences/\(bid)", "Saved Application State/\(bid).savedState",
                         "Logs/\(bid)", "LaunchAgents/\(bid).plist"] {
                candidates[relative(path)] = sharing(copy, otherwise: .exclusive)
            }
            for path in ["Containers/\(bid)", "Application Support/\(bid)", "Application Scripts/\(bid)",
                         "HTTPStorages/\(bid)", "HTTPStorages/\(bid).binarycookies",
                         "WebKit/\(bid)", "Cookies/\(bid).binarycookies"] {
                candidates[relative(path)] = sharing(copy, otherwise: .personal)
            }
            for group in [bid] + groupIDs where Self.validComponent(group) {
                candidates[relative("Group Containers/\(group)")] = .group
            }
            if let profile = Self.browserProfiles[bid.lowercased()] {
                let owner = others.first { Self.browserProfiles[$0.bundleId?.lowercased() ?? ""] == profile }
                candidates[relative("Application Support/\(profile)")] = sharing(owner ?? copy ?? sameName, otherwise: .personal)
            }
        }
        candidates[app.url.standardizedFileURL.path] = .application
    }

    func use(of item: ScanItem) -> UninstallDataUse? { candidates[item.url.standardizedFileURL.path] }

    static func current(for app: AppInfo) -> Self {
        var apps = AppCatalog.installedApps()
        var identifiers = Set<String>()
        if let id = app.bundleId {
            identifiers.insert(id)
            if let profile = browserProfiles[id.lowercased()] {
                identifiers.formUnion(browserProfiles.compactMap { $0.value == profile ? $0.key : nil })
            }
        }
        for id in identifiers {
            let workspace = NSWorkspace.shared
            let registered = workspace.urlsForApplications(withBundleIdentifier: id)
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).compactMap(\.bundleURL)
            for url in Set(registered + running) where FileManager.default.fileExists(atPath: url.path) {
                guard let actual = Bundle(url: url)?.bundleIdentifier,
                      actual.caseInsensitiveCompare(id) == .orderedSame else { continue }
                apps.append(AppInfo(url: url, name: url.deletingPathExtension().lastPathComponent, bundleId: actual))
            }
        }
        let target = app.url.resolvingSymlinksInPath().standardizedFileURL
        let others = apps.filter {
            let url = $0.url.resolvingSymlinksInPath().standardizedFileURL
            return url.path != target.path && !url.pathComponents.contains(".Trash") && !url.pathComponents.contains(".Trashes")
        }
        return Self(app: app, others: others, groupIDs: declaredGroups(at: app.url))
    }

    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }

    private static func declaredGroups(at url: URL) -> [String] {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}
