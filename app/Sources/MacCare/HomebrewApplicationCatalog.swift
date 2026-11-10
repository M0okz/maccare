import Foundation

/// Interprets metadata only: no cask Ruby, installer, uninstall or zap action is executed.
enum HomebrewApplicationCatalog {
    struct Environment {
        let systemVersion: String
        let platform: String

        static var current: Self {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let names = [11: "big_sur", 12: "monterey", 13: "ventura", 14: "sonoma", 15: "sequoia", 26: "tahoe", 27: "golden_gate"]
            #if arch(arm64)
            let prefix = "arm64_"
            #else
            let prefix = ""
            #endif
            return Self(systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                        platform: prefix + (names[os.majorVersion] ?? "unsupported"))
        }
    }

    static func updates(data: Data, apps: [InstalledUpdateApplication], environment: Environment = .current) throws -> [OutdatedItem] {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !entries.isEmpty,
              !environment.platform.hasSuffix("unsupported") else { throw URLError(.cannotParseResponse) }
        var candidates: [String: [[String: Any]]] = [:]
        for entry in entries {
            guard let token = entry["token"] as? String, !token.contains("@"),
                  entry["disabled"] as? Bool != true, entry["deprecated"] as? Bool != true else { continue }
            var selected = entry
            if let variations = entry["variations"] as? [String: [String: Any]], let variation = variations[environment.platform] {
                selected.merge(variation) { _, new in new }
            }
            guard let platforms = entry["supported_platforms"] as? [String], platforms.contains(environment.platform),
                  supportsSystem(selected, version: environment.systemVersion),
                  let rawVersion = selected["version"] as? String,
                  let version = rawVersion.split(separator: ",").first.map(String.init),
                  ApplicationReleaseVersion.normalized(version) != nil else { continue }
            let artifacts = selected["artifacts"] as? [[String: Any]] ?? []
            let filenames = Set(artifacts.flatMap { artifact -> [String] in
                guard let app = artifact["app"] as? [Any], let path = app.first as? String else { return [] }
                return [((artifact["target"] as? String ?? path) as NSString).lastPathComponent]
            })
            guard !filenames.isEmpty else { continue }
            let ids = bundleIDs(artifacts)
            for app in apps where !app.appStore && ids.contains(app.bundleID) && filenames.contains(app.url.lastPathComponent) {
                candidates[app.url.path, default: []].append(selected)
            }
        }
        return apps.compactMap { app in
            // Shared bundle IDs across editions (e.g. standard/VFS) are ambiguous: skip them.
            guard let matches = candidates[app.url.path], matches.count == 1, let cask = matches.first,
                  let rawVersion = cask["version"] as? String,
                  let version = rawVersion.split(separator: ",").first.map(String.init),
                  ApplicationReleaseVersion.isNewer(version, than: app.version),
                  let homepage = cask["homepage"] as? String, let url = URL(string: homepage),
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  let token = cask["token"] as? String else { return nil }
            return OutdatedItem(name: app.name, detail: "\(app.version) → \(version)",
                                releaseNotes: "Version détectée via le catalogue public Homebrew, utilisable sans Homebrew installé. Le téléchargement provient de l’éditeur. Consultez son site pour les nouveautés.",
                                applicationURL: app.url, downloadURL: url, catalogToken: token, artifact: artifact(cask, bundleID: app.bundleID, version: version))
        }
    }

    private static func artifact(_ cask: [String: Any], bundleID: String, version: String) -> ApplicationUpdateArtifact? {
        guard let raw = cask["url"] as? String, let url = URL(string: raw),
              ApplicationUpdatePolicy.validDownloadURL(url),
              ["zip", "dmg", "pkg"].contains(url.pathExtension.lowercased()) else { return nil }
        if let verified = VerifiedApplicationRelease.artifact(bundleID: bundleID, version: version, url: url) { return verified }
        let checksum = cask["sha256"] as? String
        let valid = checksum.flatMap { $0.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil ? $0.lowercased() : nil }
        return .init(url: url, sha256: valid)
    }

    private static func bundleIDs(_ artifacts: [[String: Any]]) -> Set<String> {
        var ids = Set<String>()
        for artifact in artifacts {
            for uninstall in artifact["uninstall"] as? [[String: Any]] ?? [] {
                if let id = uninstall["quit"] as? String { ids.insert(id) }
                if let values = uninstall["quit"] as? [String] { ids.formUnion(values) }
            }
            for zap in artifact["zap"] as? [[String: Any]] ?? [] {
                let paths = (zap["trash"] as? [String]) ?? (zap["trash"] as? String).map { [$0] } ?? []
                for path in paths {
                    let prefix = "~/Library/Preferences/"
                    guard path.hasPrefix(prefix), path.hasSuffix(".plist") else { continue }
                    let id = String(path.dropFirst(prefix.count).dropLast(".plist".count))
                    guard !id.isEmpty, !id.contains("/"), !id.contains(where: { "*?[]{}$".contains($0) }) else { continue }
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    private static func supportsSystem(_ entry: [String: Any], version: String) -> Bool {
        guard let depends = entry["depends_on"] as? [String: Any], let macos = depends["macos"] as? [String: Any] else { return true }
        for (operation, raw) in macos {
            let values = (raw as? [String]) ?? (raw as? String).map { [$0] } ?? []
            guard !values.isEmpty, values.contains(where: { required in
                guard let required = ApplicationReleaseVersion.normalized(required),
                      let version = ApplicationReleaseVersion.normalized(version) else { return false }
                let order = version.compare(required, options: .numeric)
                switch operation {
                case ">=": return order != .orderedAscending
                case ">": return order == .orderedDescending
                case "<=": return order != .orderedDescending
                case "<": return order == .orderedAscending
                case "==", "=": return order == .orderedSame
                default: return false
                }
            }) else { return false }
        }
        return true
    }
}
