import CRemoveFile
import Darwin
import Foundation

/// One-shot operation launched by an administrator authorization. Never exported over XPC.
public struct AuthorizedUninstall: Codable {
    public struct Item: Codable {
        public let path: String
        public let device: UInt64
        public let inode: UInt64
        public init(path: String, device: UInt64, inode: UInt64) {
            self.path = path; self.device = device; self.inode = inode
        }
    }
    public struct Result: Codable {
        public let path: String
        public let error: String?
        public let kept: Bool
    }
    public let uid: uid_t
    public let bundle: String
    public let bundleID: String?
    public let direct: Bool
    public let items: [Item]

    public init(uid: uid_t, bundle: String, bundleID: String?, direct: Bool, items: [Item]) {
        self.uid = uid; self.bundle = bundle; self.bundleID = bundleID; self.direct = direct; self.items = items
    }

    /// Point d’entrée du service : l’UID vient de la connexion authentifiée, jamais du message.
    public static func serviceReply(selectionJSON: String, authenticatedUID: uid_t) -> (reply: String, results: [Result]?) {
        func failure(_ message: String) -> (String, [Result]?) {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()
            return (String(decoding: data, as: UTF8.self), nil)
        }
        guard selectionJSON.utf8.count <= 2_000_000,
              let request = try? JSONDecoder().decode(AuthorizedUninstall.self, from: Data(selectionJSON.utf8)),
              request.items.count <= 1_000 else { return failure("Sélection invalide.") }
        guard request.uid == authenticatedUID else { return failure("La sélection ne correspond pas à la session.") }
        do {
            let results = try request.execute()
            let data = try JSONEncoder().encode(results)
            return (String(decoding: data, as: UTF8.self), results)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    public func execute() throws -> [Result] {
        var console = stat()
        guard uid > 0, stat("/dev/console", &console) == 0, console.st_uid == uid,
              let account = getpwuid(uid), let directory = account.pointee.pw_dir,
              !items.isEmpty, Set(items.map(\.path)).count == items.count else { throw Failure.invalid }
        let home = String(cString: directory)
        let app = URL(fileURLWithPath: bundle)
        guard ["/Applications", home + "/Applications"].contains(app.deletingLastPathComponent().path),
              app.pathExtension == "app", bundle == app.path, validPath(bundle),
              bundleID != "org.maccare.app", !["MacCare.app", "MacCare Dev.app"].contains(app.lastPathComponent) else {
            throw Failure.invalid
        }

        // Another copy may have appeared while the authorization sheet was open.
        let other = bundleID.flatMap { id -> URL? in
            for root in ["/Applications", home + "/Applications"] {
                let directory = URL(fileURLWithPath: root)
                let apps = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                if let copy = apps.first(where: {
                    $0.pathExtension == "app" && $0.path != bundle &&
                    Bundle(url: $0)?.bundleIdentifier?.caseInsensitiveCompare(id) == .orderedSame
                }) { return copy }
            }
            return nil
        }
        let sorted = items.filter { $0.path == bundle } + items.filter { $0.path != bundle }
        var bundleFailed = false
        return sorted.map { item in
            if bundleFailed {
                return Result(path: item.path, error: "Donnée conservée car l’application n’a pas été retirée.", kept: true)
            }
            if let other, item.path != bundle {
                return Result(path: item.path, error: "Donnée utilisée par " + other.path, kept: true)
            }
            do {
                guard validPath(item.path), allowed(item.path, app: app, home: home) else { throw Failure.invalid }
                try move(item, home: home)
                return Result(path: item.path, error: nil, kept: false)
            } catch {
                if item.path == bundle { bundleFailed = true }
                return Result(path: item.path, error: error.localizedDescription, kept: false)
            }
        }
    }

    private func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("\0") && !path.contains("//") && !path.hasSuffix("/")
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    private func allowed(_ path: String, app: URL, home: String) -> Bool {
        if path == bundle { return true }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        let name = url.lastPathComponent.lowercased()
        if parent.hasPrefix(home + "/Library/") {
            let relative = String(parent.dropFirst((home + "/Library/").count))
            let locations = ["Caches", "Logs", "Preferences", "Preferences/ByHost", "Saved Application State", "LaunchAgents",
                             "Containers", "Group Containers", "Application Scripts", "Application Support",
                             "HTTPStorages", "WebKit", "Cookies",
                             "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"]
            if locations.contains(relative) { return true }
            let profiles = ["Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "BraveSoftware/Brave-Browser"]
            return profiles.contains { path == home + "/Library/Application Support/" + $0 }
        }
        if parent.hasPrefix("/private/var/folders/") {
            let parts = parent.split(separator: "/")
            guard parts.count == 6, ["T", "C"].contains(parts.last) else { return false }
            var info = stat()
            return lstat(parent, &info) == 0 && info.st_uid == uid
        }
        guard let id = bundleID?.lowercased(), id.contains("."), !id.hasPrefix("com.apple."),
              !name.hasPrefix("com.apple.") else { return false }
        switch parent {
        case "/Library/Preferences": return name == id + ".plist"
        case "/Library/Caches": return name == id
        case "/Library/Application Support": return name == id || name == app.deletingPathExtension().lastPathComponent.lowercased() + " helper"
        case "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools":
            guard parent.hasSuffix("Tools") || name.hasSuffix(".plist") else { return false }
            let label = parent.hasSuffix("Tools") ? name : String(name.dropLast(6))
            return label == id || label == id + "helper" || label.hasPrefix(id + ".")
        default: return false
        }
    }

    private func move(_ item: Item, home: String) throws {
        let url = URL(fileURLWithPath: item.path)
        let name = url.lastPathComponent
        let source = try openDirectory(url.deletingLastPathComponent().path)
        defer { close(source) }
        func matches(_ dir: Int32, _ leaf: String) -> Bool {
            var s = stat()
            return fstatat(dir, leaf, &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_mode & S_IFMT != S_IFLNK
                && s.st_flags & UInt32(SF_RESTRICTED) == 0 && UInt64(UInt32(bitPattern: s.st_dev)) == item.device
                && UInt64(s.st_ino) == item.inode
        }
        guard matches(source, name) else { throw Failure.changed }
        // Irreversible recursion only takes place inside a freshly created private directory.
        // Corbeille operations rename directly into the initiating user's directory.
        let folder: String
        if direct {
            var template = Array("/private/tmp/maccare-uninstall.XXXXXXXX".utf8CString)
            guard mkdtemp(&template) != nil else { throw posix() }
            folder = String(cString: template)
        } else {
            folder = home + "/.Trash"
        }
        defer { if direct { _ = rmdir(folder) } }
        let destination = try openDirectory(folder)
        defer { close(destination) }
        var target = stat()
        guard fstat(destination, &target) == 0, target.st_uid == (direct ? geteuid() : uid),
              target.st_mode & 0o077 == 0 else { throw Failure.invalid }

        var leaf = name
        if renameatx_np(source, name, destination, leaf, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST, !direct else { throw posix() }
            let ext = url.pathExtension
            leaf = url.deletingPathExtension().lastPathComponent + " " + UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
            guard renameatx_np(source, name, destination, leaf, UInt32(RENAME_EXCL)) == 0 else { throw posix() }
        }
        do {
            guard matches(destination, leaf) else { throw Failure.changed }
            if direct && removefileat(destination, leaf, nil, removefile_flags_t(REMOVEFILE_RECURSIVE)) != 0 { throw posix() }
        } catch {
            guard renameatx_np(destination, leaf, source, name, UInt32(RENAME_EXCL)) == 0 else {
                throw Failure.recovery(folder + "/" + leaf)
            }
            throw error
        }
    }

    private func openDirectory(_ path: String) throws -> Int32 {
        // Search permission suffices for descriptor-relative moves. Opening ~/.Trash for
        // listing would unnecessarily require Full Disk Access on recent macOS versions.
        let fd = open(path, O_SEARCH | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw posix() }
        return fd
    }
    private func posix() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private enum Failure: LocalizedError {
        case invalid, changed, recovery(String)
        var errorDescription: String? {
            switch self {
            case .invalid: return "Ce chemin est hors de la sélection applicative autorisée."
            case .changed: return "L’élément a changé depuis l’analyse ou macOS le protège."
            case .recovery(let path): return "Le retrait est incomplet. L’élément est récupérable à cet emplacement : \(path)"
            }
        }
    }
}
