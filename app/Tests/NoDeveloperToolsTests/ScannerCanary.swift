import Foundation
import Darwin

// This standalone integration test compiles the real scanner with a command
// launcher that fails instead of invoking an Xcode shim or installing anything.
struct ScanItem { let size_bytes: UInt64 }
struct CleaningCategory {
    let id: String
    let baseTOML: String
    static let all: [CleaningCategory] = []
}
enum Engine {
    static func scan(ruleTOML: String) throws -> [ScanItem] { [] }
}
enum ApplicationReleaseVersion {
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: .numeric) == .orderedDescending
    }
}
enum SystemTools {
    struct Output {
        let stdout: String
        var ok: Bool { false }
    }
    static func run(_ path: String, _ arguments: [String], environment: [String: String] = [:]) -> Output {
        FileHandle.standardError.write(Data("FAIL: application scan requested an external command: \(path) \(arguments.joined(separator: " "))\n".utf8))
        exit(EXIT_FAILURE)
    }
}

@main
struct ScannerCanary {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        let binaries = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binaries.appendingPathComponent("Fixture"))
        let info = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "org.maccare.qa.no-developer-tools",
                    "CFBundleName": "Fixture", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "10.15"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let snapshot = ApplicationInsightsReader.scan(apps: [.init(url: app, name: "Fixture", bundleId: info["CFBundleIdentifier"])], running: [])
        guard snapshot.unknownCompatibility == 0, snapshot.incompatible.isEmpty else {
            FileHandle.standardError.write(Data("FAIL: native executable was not classified without developer tools\n".utf8))
            exit(EXIT_FAILURE)
        }
        print("PASS: real application scanner classified a native executable without launching a command")
        if CommandLine.arguments.contains("--installed-apps") {
            let installed = AppCatalog.installedApps()
            let result = ApplicationInsightsReader.scan(apps: installed, running: [])
            print("PASS: real inventory and scanner inspected \(installed.count) installed apps without launching a command (\(result.unknownCompatibility) unknown architectures)")
        }
    }
}
