import CryptoKit
import Darwin
import Foundation
import MacCareHelperProtocol
import MacCareMaintenance

enum UninstallAuthorization {
    static let authorizationScript = """
    on run argv
        try
            return do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges
        on error number -128
            return "cancelled"
        end try
    end run
    """

    static func run(_ items: [ScanItem], app: AppInfo, direct: Bool) async throws -> [AuthorizedUninstall.Result] {
        let request = AuthorizedUninstall(uid: getuid(), bundle: app.url.path, bundleID: app.bundleId,
                                          direct: direct, items: items.map {
            .init(path: $0.path, device: $0.identity.device, inode: $0.identity.inode)
        })
        let payload = try JSONEncoder().encode(request)
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MacCareHelper")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        let manifest = work.appendingPathComponent("selection.json")
        try payload.write(to: manifest, options: .withoutOverwriting)
        let command = stagedCommand(helper: helper, manifest: manifest, payload: payload)
        let prompt = "MacCare souhaite retirer les éléments cochés pour \(app.name)."
        let json = try await ApplicationUpdateCommand.run("/usr/bin/osascript", ["-e", authorizationScript, command, prompt],
                                                           outputPolicy: .complete(maximumBytes: 2_000_000))
        if json.trimmingCharacters(in: .whitespacesAndNewlines) == "cancelled" {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Autorisation administrateur annulée."])
        }
        return try JSONDecoder().decode([AuthorizedUninstall.Result].self, from: Data(json.utf8))
    }

    /// The helper verifies the digest of its actual stdin before decoding the selection. Verify
    /// the signature of the staged executable, never a mutable executable verified before copy.
    static func stagedCommand(helper: URL, manifest: URL, payload: Data) -> String {
        func quoted(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return """
        set -eu
        umask 077
        stage=$(/usr/bin/mktemp -d /private/tmp/maccare-authorize.XXXXXXXX)
        trap '/bin/rm -rf -- "$stage"' EXIT
        /bin/cp -L \(quoted(helper.path)) "$stage/helper"
        /bin/chmod 500 "$stage/helper"
        /usr/bin/codesign --verify --strict --test-requirement \(quoted("=" + HelperIdentity.helperRequirement)) "$stage/helper"
        "$stage/helper" --uninstall-selection \(digest) < \(quoted(manifest.path))
        """
    }
}
