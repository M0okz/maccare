import Foundation
import Darwin

/// Identifiers and groups are read while the selected bundle still exists.
struct UninstallArtifacts {
    var embeddedIDs = Set<String>()
    var groups = Set<String>()

    // Login helpers can leave files across an app update that no longer ships the helper.
    static func legacyLoginIDs(for id: String) -> Set<String> { [id + ".LaunchAtLoginHelper", id + ".LoginHelper"] }

    init(app: AppInfo) {
        groups = Set(ApplicationGroups.declared(at: app.url))
        guard let parentID = app.bundleId, Self.validID(parentID) else { return }
        let contents = app.url.appendingPathComponent("Contents")
        for location in ["Library/LoginItems", "PlugIns", "XPCServices", "Frameworks", "Helpers"] {
            let root = contents.appendingPathComponent(location)
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children where ["app", "appex", "xpc"].contains(child.pathExtension.lowercased()) {
                let url = root.appendingPathComponent(child.lastPathComponent)
                guard Self.noLinkedAncestor(url, under: app.url),
                      let id = Bundle(url: url)?.bundleIdentifier, Self.validID(id),
                      id.lowercased().hasPrefix(parentID.lowercased() + ".") else { continue }
                embeddedIDs.insert(id)
                groups.formUnion(ApplicationGroups.declared(at: url))
            }
        }
    }

    private static func noLinkedAncestor(_ url: URL, under root: URL) -> Bool {
        var entry = url
        while entry.path != root.path {
            var info = stat()
            guard entry.path.hasPrefix(root.path + "/"), lstat(entry.path, &info) == 0,
                  info.st_mode & S_IFMT != S_IFLNK else { return false }
            entry.deleteLastPathComponent()
        }
        return true
    }

    static func validID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
            }
        }
    }

    static var darwinDirectories: [URL] {
        [_CS_DARWIN_USER_CACHE_DIR, _CS_DARWIN_USER_TEMP_DIR].compactMap { key in
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            let length = confstr(key, &buffer, buffer.count)
            guard length > 1, length <= buffer.count else { return nil }
            // /var is a system alias. Resolve only Apple's root, never the candidate.
            guard let resolved = realpath(buffer, nil) else { return nil }
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
    }

    /// Machine-wide items need an app-specific launch label and a matching executable location.
    static func machineItems(app: AppInfo, library: URL) -> Set<URL> {
        guard let bundleID = app.bundleId, validID(bundleID), !bundleID.lowercased().hasPrefix("com.apple."),
              UninstallReview.validComponent(app.name) else { return [] }
        let supportRoot = library.appendingPathComponent("Application Support")
        let supportNames = Set([bundleID, app.name + " Helper"])
        let tools = library.appendingPathComponent("PrivilegedHelperTools")
        var found: Set<URL> = [
            supportRoot.appendingPathComponent(bundleID),
            library.appendingPathComponent("Caches/" + bundleID),
            library.appendingPathComponent("Preferences/" + bundleID + ".plist")
        ]
        let base = bundleID.lowercased()
        for directory in ["LaunchAgents", "LaunchDaemons"] {
            let root = library.appendingPathComponent(directory)
            let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.pathExtension == "plist" {
                let plist = root.appendingPathComponent(entry.lastPathComponent)
                let label = plist.deletingPathExtension().lastPathComponent
                let lower = label.lowercased()
                guard validID(label), lower == base || lower == base + "helper" || lower.hasPrefix(base + "."),
                      Self.noLinkedAncestor(plist, under: library),
                      let bytes = try? Data(contentsOf: plist),
                      let info = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
                      info["Label"] as? String == label,
                      let program = (info["Program"] as? String) ?? (info["ProgramArguments"] as? [String])?.first,
                      program.hasPrefix("/") else { continue }
                let url = URL(fileURLWithPath: program)
                guard !program.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { continue }
                if url.path.hasPrefix(app.url.path + "/Contents/") {
                    found.insert(plist)
                } else if url.deletingLastPathComponent().path == tools.path && url.lastPathComponent == label {
                    found.formUnion([plist, url])
                } else if let name = supportNames.first(where: { url.path.hasPrefix(supportRoot.appendingPathComponent($0).path + "/") }) {
                    found.formUnion([plist, supportRoot.appendingPathComponent(name)])
                }
            }
        }
        return found
    }
}
