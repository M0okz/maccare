import Foundation

struct ApplicationUpdateArtifact: Hashable, Sendable {
    let url: URL
    var sha256: String? = nil
}

enum ApplicationUpdateFailure: LocalizedError {
    case refused(String)
    var errorDescription: String? { if case .refused(let reason) = self { return reason }; return nil }
}

struct ApplicationUpdateTarget: Hashable, Sendable {
    let url: URL
    let bundleID: String
    let version: String
    let expectedVersion: String

    static func readVersion(_ info: [String: Any]) -> String? {
        (info["ArtCraftLauncherVersion"] ?? info["CFBundleShortVersionString"]) as? String
    }

    static func info(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ApplicationUpdateFailure.refused("Le paquet de l’application est illisible.")
        }
        return info
    }
}

/// The updater replaces an existing app only. No catalog-supplied destination or script is accepted.
struct ApplicationUpdatePolicy: Sendable {
    var roots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    var protectedBundleIDs: Set<String> = ["org.maccare.app"]

    func target(url: URL, expectedVersion: String) throws -> ApplicationUpdateTarget {
        let path = url.standardizedFileURL
        guard path.pathExtension == "app", path.path == path.resolvingSymlinksInPath().path,
              roots.contains(where: { path.path.hasPrefix($0.standardizedFileURL.path + "/") }),
              FileManager.default.fileExists(atPath: path.path) else {
            throw ApplicationUpdateFailure.refused("Seules les applications existantes dans Applications peuvent être remplacées.")
        }
        let info = try ApplicationUpdateTarget.info(at: path)
        guard let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              !protectedBundleIDs.contains(id), let version = ApplicationUpdateTarget.readVersion(info),
              ApplicationReleaseVersion.isNewer(expectedVersion, than: version) else {
            throw ApplicationUpdateFailure.refused("La version installée a changé ou cette application utilise un autre mécanisme de mise à jour. Actualisez la liste.")
        }
        return .init(url: path, bundleID: id, version: version, expectedVersion: expectedVersion)
    }

    func validateCandidate(at url: URL, target: ApplicationUpdateTarget) throws {
        let info = try ApplicationUpdateTarget.info(at: url)
        guard info["CFBundleIdentifier"] as? String == target.bundleID,
              let version = ApplicationUpdateTarget.readVersion(info),
              let normalized = ApplicationReleaseVersion.normalized(version),
              let expected = ApplicationReleaseVersion.normalized(target.expectedVersion),
              ApplicationReleaseVersion.isNewer(version, than: target.version),
              normalized.compare(expected, options: .numeric) != .orderedAscending else {
            throw ApplicationUpdateFailure.refused("Le téléchargement ne correspond pas à l’application ou à la version attendue.")
        }
        if let minimum = info["LSMinimumSystemVersion"] as? String {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            if ApplicationReleaseVersion.isNewer(minimum, than: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") {
                throw ApplicationUpdateFailure.refused("La nouvelle version nécessite un macOS plus récent.")
            }
        }
    }

    static func managedCaskMatches(directory: URL, target: URL) -> Bool {
        guard let versions = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        for version in versions {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            if entries.contains(where: { $0.pathExtension == "app" && $0.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path }) { return true }
        }
        return false
    }

    static func validToken(_ token: String) -> Bool {
        token.range(of: "^[a-z0-9][a-z0-9+.-]*$", options: .regularExpression) != nil && token.count < 160
    }

    static func validDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    static func validArchivePaths(_ paths: [String]) -> Bool {
        !paths.isEmpty && paths.allSatisfy { path in
            !path.hasPrefix("/") && !path.contains("\\") && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        }
    }
}
