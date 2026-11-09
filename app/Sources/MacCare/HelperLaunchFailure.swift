import Foundation
import Security
import MacCareHelperProtocol

/// A generic timeout is ambiguous. Only this observed configuration failure permits explicit repair.
enum HelperLaunchFailure {
    static func isConfirmed(in output: String) -> Bool {
        guard output.utf8.count <= 32_768,
              output.hasPrefix("system/\(HelperIdentity.machService) = {") else { return false }
        let rows = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !rows.contains(where: { $0.hasPrefix("pid = ") }),
              rows.contains("job state = spawn failed"),
              rows.contains("last exit code = 78: EX_CONFIG"),
              rows.contains("parent bundle identifier = org.maccare.app"),
              rows.contains("program identifier = Contents/MacOS/MacCareHelper (mode: 2)"),
              rows.contains("MACCARE_BATTERY_RECOVERY => 1") else { return false }
        return true
    }

    /// Validate the packaged replacement before removing the old registration.
    /// Its startup restores the existing root journal before accepting charge commands.
    static func packagedRecoveryIsValid(at bundle: URL) -> Bool {
        let descriptor = bundle.appendingPathComponent("Contents/Library/LaunchDaemons/\(HelperIdentity.daemonPlist)")
        guard let data = try? Data(contentsOf: descriptor),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == HelperIdentity.machService,
              plist["BundleProgram"] as? String == "Contents/MacOS/MacCareHelper",
              let environment = plist["EnvironmentVariables"] as? [String: String],
              environment["MACCARE_BATTERY_RECOVERY"] == "1" else { return false }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let executable = bundle.appendingPathComponent("Contents/MacOS/MacCareHelper")
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString((HelperIdentity.helperRequirement +
                  " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}
