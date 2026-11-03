import Foundation

/// Petits utilitaires système : exécution d'un binaire (jamais via un shell, **jamais** sudo)
/// et localisation d'exécutables. Une app GUI lancée par le Finder n'hérite pas du PATH du
/// shell : on cherche donc les binaires dans des emplacements connus (dont Homebrew).
enum SystemTools {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    /// Exécute `launchPath` avec `args`. Renvoie code de sortie + sorties. Aucune entrée shell.
    static func run(_ launchPath: String, _ args: [String], environment: [String: String] = [:]) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(
            status: process.terminationStatus,
            stdout: String(decoding: oData, as: UTF8.self),
            stderr: String(decoding: eData, as: UTF8.self)
        )
    }

    /// Emplacements habituels des binaires (Apple Silicon + Intel + système).
    private static let binDirs = [
        "/opt/homebrew/bin", "/usr/local/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    /// Chemin absolu d'un exécutable présent, ou nil.
    static func locate(_ name: String) -> String? {
        for dir in binDirs {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
