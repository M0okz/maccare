import Foundation
import AppKit
import Security
import CryptoKit

private final class ApplicationDownloadProgress: NSObject, URLSessionDownloadDelegate {
    let report: @Sendable (Double?) -> Void
    init(report: @escaping @Sendable (Double?) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 2_147_483_648 { downloadTask.cancel(); return }
        report(totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(ApplicationUpdatePolicy.validDownloadURL) == true ? request : nil)
    }
}

struct PreparedApplicationUpdate: Sendable {
    let root: URL
    let application: URL?
    let package: URL?
    let target: ApplicationUpdateTarget
    let teamID: String
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

enum ApplicationUpdateArchive {
    typealias Fetch = @Sendable (URL, URL, @escaping @Sendable (Double?) -> Void) async throws -> Void

    static func validateZIPPaths(in archive: URL) async throws {
        let listing = try await ApplicationUpdateCommand.run("/usr/bin/zipinfo", ["-1", archive.path], outputPolicy: .complete(maximumBytes: 16 * 1024 * 1024))
        guard ApplicationUpdatePolicy.validArchivePaths(listing.components(separatedBy: .newlines).filter { !$0.isEmpty }) else {
            throw ApplicationUpdateFailure.refused("L’archive contient des chemins non autorisés.")
        }
    }

    static func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        guard ApplicationUpdatePolicy.validDownloadURL(url) else { throw ApplicationUpdateFailure.refused("Le téléchargement doit provenir d’une adresse HTTPS.") }
        let observer = ApplicationDownloadProgress(report: progress)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.setValue("MacCare-Application-Update", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await session.download(for: request, delegate: observer)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url.map(ApplicationUpdatePolicy.validDownloadURL) == true,
              (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_147_483_648 else {
            throw ApplicationUpdateFailure.refused("Le téléchargement a échoué ou dépasse la taille autorisée.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    static func teamID(at url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess else {
            throw ApplicationUpdateFailure.refused("La signature de l’application est absente ou invalide.")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else {
            throw ApplicationUpdateFailure.refused("L’identité de l’éditeur ne peut pas être vérifiée.")
        }
        return team
    }

    static func checkHash(of url: URL, expected: String?) throws {
        guard let expected else { return }
        guard expected.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
            throw ApplicationUpdateFailure.refused("L’empreinte du téléchargement est invalide.")
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else {
            throw ApplicationUpdateFailure.refused("L’empreinte du téléchargement ne correspond pas. L’application installée est conservée.")
        }
    }

    static func prepare(artifact: ApplicationUpdateArtifact, target: ApplicationUpdateTarget,
                        policy: ApplicationUpdatePolicy = .init(), fetch: @escaping Fetch = { url, destination, progress in try await download(url, to: destination, progress: progress) },
                        progress: @escaping @Sendable (Double?) -> Void = { _ in },
                        verifying: @escaping @Sendable () -> Void = {}) async throws -> PreparedApplicationUpdate {
        guard ApplicationUpdatePolicy.validDownloadURL(artifact.url) else { throw ApplicationUpdateFailure.refused("Adresse de téléchargement invalide.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacCare-Application-Update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let team = try await Task.detached { try teamID(at: target.url) }.value
            let kind = artifact.url.pathExtension.lowercased()
            guard ["zip", "dmg", "pkg"].contains(kind) else { throw ApplicationUpdateFailure.refused("Ce format nécessite l’installateur de l’éditeur.") }
            let archive = root.appendingPathComponent("download." + kind)
            try await fetch(artifact.url, archive, progress)
            try Task.checkCancellation()
            verifying()
            try await Task.detached { try checkHash(of: archive, expected: artifact.sha256) }.value
            if kind == "pkg" {
                let report = try await ApplicationUpdateCommand.run("/usr/sbin/pkgutil", ["--check-signature", archive.path])
                let leaf = report.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("1. Developer ID Installer:") }
                guard leaf?.trimmingCharacters(in: .whitespaces).hasSuffix("(" + team + ")") == true else { throw ApplicationUpdateFailure.refused("L’installateur n’est pas signé par le même éditeur que l’application.") }
                _ = try await ApplicationUpdateCommand.run("/usr/sbin/spctl", ["--assess", "--type", "install", archive.path])
                return .init(root: root, application: nil, package: archive, target: target, teamID: team)
            }
            let unpacked = root.appendingPathComponent("unpacked")
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            var mounted = false
            if kind == "dmg" {
                _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", unpacked.path, archive.path])
                mounted = true
            } else {
                try await validateZIPPaths(in: archive)
                _ = try await ApplicationUpdateCommand.run("/usr/bin/tar", ["-xf", archive.path, "-C", unpacked.path, "--no-same-owner"])
            }
            // Detach on every exit, before the temporary root is removed.
            do {
                let staged = root.appendingPathComponent("Replacement.app")
                try await Task.detached {
                    let candidates = try candidates(in: unpacked, bundleID: target.bundleID)
                    guard candidates.count == 1, let candidate = candidates.first else {
                        throw ApplicationUpdateFailure.refused("L’archive ne contient pas une application unique correspondant à celle installée.")
                    }
                    try FileManager.default.copyItem(at: candidate, to: staged)
                    try policy.validateCandidate(at: staged, target: target)
                    guard try teamID(at: staged) == team else { throw ApplicationUpdateFailure.refused("L’identité de l’éditeur a changé. L’application installée est conservée.") }
                }.value
                _ = try await ApplicationUpdateCommand.run("/usr/sbin/spctl", ["--assess", "--type", "execute", staged.path])
                try validateArchitecture(at: executable(in: staged))
                if mounted { _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil", ["detach", "-quiet", unpacked.path]); mounted = false }
                try Task.checkCancellation()
                return .init(root: root, application: staged, package: nil, target: target, teamID: team)
            } catch {
                if mounted { _ = try? await ApplicationUpdateCommand.run("/usr/bin/hdiutil", ["detach", "-quiet", unpacked.path]) }
                throw error
            }
        } catch { try? FileManager.default.removeItem(at: root); throw error }
    }

    /// Reject unknown or unsupported payloads without launching a developer tool.
    static func validateArchitecture(at executableURL: URL) throws {
        guard let architectures = ExecutableArchitectures.read(at: executableURL) else {
            throw ApplicationUpdateFailure.refused("L’architecture de la nouvelle version n’a pas pu être vérifiée. L’application installée est conservée.")
        }
        #if arch(arm64)
        let supported: Set<String> = ["arm64", "x86_64"]
        #else
        let supported: Set<String> = ["x86_64"]
        #endif
        guard !architectures.isDisjoint(with: supported) else {
            throw ApplicationUpdateFailure.refused("La nouvelle version ne prend pas en charge l’architecture de ce Mac.")
        }
    }

    private static func executable(in app: URL) throws -> URL {
        let info = try ApplicationUpdateTarget.info(at: app)
        guard let name = info["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw ApplicationUpdateFailure.refused("Le binaire principal du téléchargement est invalide.")
        }
        return app.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
    }

    private static func candidates(in root: URL, bundleID: String) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw ApplicationUpdateFailure.refused("L’archive sort de son dossier de préparation.") }
            if url.pathExtension == "app" {
                enumerator.skipDescendants()
                if (try? ApplicationUpdateTarget.info(at: url)["CFBundleIdentifier"] as? String) == bundleID { result.append(url) }
            }
        }
        return result
    }

    @MainActor static func replace(_ prepared: PreparedApplicationUpdate, policy: ApplicationUpdatePolicy = .init()) async throws {
        guard let replacement = prepared.application else { throw ApplicationUpdateFailure.refused("Le paquet nécessite son installateur.") }
        // Revalidate the destination immediately before using the scoped macOS file authorization.
        let current = try policy.target(url: prepared.target.url, expectedVersion: prepared.target.expectedVersion)
        guard current == prepared.target, try teamID(at: current.url) == prepared.teamID else { throw ApplicationUpdateFailure.refused("L’application installée a changé. Relancez la vérification.") }
        guard !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.resolvingSymlinksInPath() == current.url.resolvingSymlinksInPath() }) else {
            throw ApplicationUpdateFailure.refused("Quittez d’abord l’application, puis relancez la mise à jour. MacCare ne la ferme pas automatiquement.")
        }
        let manager: FileManager
        if FileManager.default.isWritableFile(atPath: current.url.deletingLastPathComponent().path) && FileManager.default.isWritableFile(atPath: current.url.path) {
            manager = .default
        } else {
            let authorization = try await NSWorkspace.shared.requestAuthorization(to: .replaceFile)
            manager = FileManager(authorization: authorization)
        }
        let finalTarget = try policy.target(url: current.url, expectedVersion: current.expectedVersion)
        guard finalTarget == current, try teamID(at: current.url) == prepared.teamID,
              try teamID(at: replacement) == prepared.teamID, !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.resolvingSymlinksInPath() == current.url.resolvingSymlinksInPath() }) else {
            throw ApplicationUpdateFailure.refused("L’application a changé ou a été ouverte pendant l’autorisation. Relancez la mise à jour.")
        }
        try policy.validateCandidate(at: replacement, target: prepared.target)
        // Atomic replacement preserves the previous bundle if replacement fails. User data is untouched.
        _ = try manager.replaceItemAt(current.url, withItemAt: replacement, backupItemName: nil, options: [])
        try policy.validateCandidate(at: current.url, target: prepared.target)
        guard try teamID(at: current.url) == prepared.teamID else { throw ApplicationUpdateFailure.refused("La vérification après installation a échoué.") }
    }
}
