import Darwin
import Foundation

public struct MaintenanceCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let timeout: TimeInterval
    public init(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) {
        self.executable = executable; self.arguments = arguments; self.timeout = timeout
    }
}

public struct MaintenanceCommandOutput: Sendable {
    public let status: Int32
    public let text: String
    public let timedOut: Bool
    public var ok: Bool { status == 0 && !timedOut }
    public init(status: Int32, text: String = "", timedOut: Bool = false) {
        self.status = status; self.text = text; self.timedOut = timedOut
    }
}

/// Borné en durée, sortie sur fichier privé pour éviter le blocage de pipes pleins.
public enum MaintenanceCommandRunner {
    public static func run(_ command: MaintenanceCommand) -> MaintenanceCommandOutput {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("maccare-maintenance-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("output")
            guard fm.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                return .init(status: -1, text: "Impossible de préparer le journal temporaire.")
            }
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = handle
            // Les outils Apple ne reçoivent ni PATH ni variables de bibliothèque de l’appelant.
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            try process.run()
            let timedOut = done.wait(timeout: .now() + command.timeout) == .timedOut
            if timedOut && process.isRunning {
                process.terminate()
                if done.wait(timeout: .now() + 2) == .timedOut && process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = done.wait(timeout: .now() + 2)
                }
            }
            let reader = try FileHandle(forReadingFrom: outputURL)
            defer { try? reader.close() }
            let data = try reader.read(upToCount: 64 * 1024) ?? Data()
            return .init(status: process.isRunning ? -1 : process.terminationStatus,
                         text: String(decoding: data, as: UTF8.self), timedOut: timedOut)
        } catch { return .init(status: -1, text: error.localizedDescription) }
    }
}
