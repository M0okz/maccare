import Foundation
import MacCareHelperProtocol

/// GUI-initiated commands use argument arrays and one output pipe, with no password capture.
enum ApplicationUpdateCommand {
    enum OutputPolicy: Sendable {
        case tail
        case complete(maximumBytes: Int)
    }
    // codesign/csreq require = to distinguish inline text from a requirement file.
    static let appStoreSigningRequirement = "=anchor apple generic and identifier \"org.maccare.mas\" and certificate leaf[subject.OU] = \"\(HelperIdentity.teamID)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"

    static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:], workingDirectory: URL? = nil, outputPolicy: OutputPolicy = .tail) async throws -> String {
        if case .complete(let maximumBytes) = outputPolicy, maximumBytes <= 0 {
            throw ApplicationUpdateFailure.refused("La limite de lecture est invalide.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = workingDirectory
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
                do {
                    try process.run()
                    var output = Data()
                    var overflow = false
                    while true {
                        let chunk = pipe.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        switch outputPolicy {
                        case .tail:
                            output.append(chunk)
                            if output.count > 128_000 { output = Data(output.suffix(128_000)) }
                        case .complete(let maximumBytes):
                            if !overflow && chunk.count <= maximumBytes - output.count {
                                output.append(chunk)
                            } else {
                                overflow = true
                                output.removeAll(keepingCapacity: false)
                            }
                        }
                    }
                    process.waitUntilExit()
                    // Drain even after overflow so the child cannot block on its output pipe.
                    // Structured metadata must fail explicitly, never return a partial record.
                    guard !overflow else {
                        throw ApplicationUpdateFailure.refused("La liste des fichiers de l’archive dépasse la limite autorisée. L’application installée est conservée.")
                    }
                    let text = String(decoding: output, as: UTF8.self)
                    guard process.terminationStatus == 0 else {
                        throw ApplicationUpdateFailure.refused(String(text.suffix(2500)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "La mise à jour a été interrompue ou refusée." : String(text.suffix(2500)))
                    }
                    continuation.resume(returning: text)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func appStoreCommand(executable: URL, id: UInt64) throws -> String {
        guard id > 0, executable.isFileURL, executable.lastPathComponent == "mas" else {
            throw ApplicationUpdateFailure.refused("Identifiant App Store invalide.")
        }
        func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return shellQuote(executable.path) + " update --force " + String(id)
    }

    static func appStorePrivilegedCommand(executable: URL, id: UInt64) throws -> String {
        _ = try appStoreCommand(executable: executable, id: id)
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // Copy first into a root-owned, private directory, THEN validate and execute that copy.
        // A user-writable source cannot be swapped between signature validation and root execution.
        return """
        set -eu
        export MAS_NO_AUTO_INDEX=1
        maccare_mas_stage=$(/usr/bin/mktemp -d /private/tmp/maccare-mas.XXXXXXXX)
        trap '/bin/rm -rf -- "$maccare_mas_stage"' EXIT
        /bin/cp -L \(quoted(executable.path)) "$maccare_mas_stage/mas"
        /bin/chmod 500 "$maccare_mas_stage/mas"
        /usr/bin/codesign --verify --strict --test-requirement \(quoted(appStoreSigningRequirement)) "$maccare_mas_stage/mas"
        "$maccare_mas_stage/mas" update --force \(id)
        """
    }

    static func appStoreAuthorizationScript(executable: URL, id: UInt64) throws -> String {
        let command = try appStorePrivilegedCommand(executable: executable, id: id)
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        return "do shell script \"\(literal)\" with administrator privileges"
    }
}
