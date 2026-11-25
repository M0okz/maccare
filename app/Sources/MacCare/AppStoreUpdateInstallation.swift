import Foundation
import Darwin

enum AppStoreUpdateInstallation {
    /// A submitted Store transaction can finish after its AppleScript client stops waiting.
    static func run(_ executable: String, _ arguments: [String], target: ApplicationUpdateTarget,
                    timeout: Duration = .seconds(120), poll: Duration = .seconds(1),
                    confirmationGrace: Duration = .seconds(10)) async throws -> Bool {
        try Task.checkCancellation()
        let policy = ApplicationUpdatePolicy()
        func isInstalled() -> Bool { (try? policy.validateCandidate(at: target.url, target: target)) != nil }
        if isInstalled() { return true }

        // A descendant can keep a pipe open after osascript exits. Only read the error tail on failure.
        guard let file = tmpfile() else { throw CocoaError(.fileWriteUnknown) }
        defer { fclose(file) }
        let errors = FileHandle(fileDescriptor: fileno(file), closeOnDealloc: false)
        let client = Process()
        client.executableURL = URL(fileURLWithPath: executable)
        client.arguments = arguments
        client.standardInput = FileHandle.nullDevice
        client.standardOutput = FileHandle.nullDevice
        client.standardError = errors
        try client.run()
        defer { if client.isRunning { client.terminate() } }

        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: timeout)
        var commandFinished = false
        while true {
            if isInstalled() { return true }
            if Task.isCancelled { return false }
            if !commandFinished && !client.isRunning {
                guard client.terminationStatus == 0 else {
                    let size = try errors.seekToEnd()
                    try errors.seek(toOffset: size > 2500 ? size - 2500 : 0)
                    let detail = String(decoding: try errors.read(upToCount: 2500) ?? Data(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw ApplicationUpdateFailure.refused(detail.isEmpty ? "La demande de mise à jour App Store a échoué." : detail)
                }
                commandFinished = true
                deadline = min(deadline, clock.now.advanced(by: confirmationGrace))
            }
            guard clock.now < deadline else { return false }
            do { try await clock.sleep(until: min(deadline, clock.now.advanced(by: poll))) }
            catch is CancellationError { return isInstalled() }
        }
    }
}
