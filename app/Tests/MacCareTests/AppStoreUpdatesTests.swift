import Foundation
import Testing
@testable import MacCare

struct AppStoreUpdatesTests {
    private let updates = """
    {"adamID":361309726,"name":"Pages","version":"15.3","newVersion":"15.4","ignored":"metadata"}
    {"adamID":497799835,"name":"Xcode (Beta)","version":"27.1","newVersion":"27.2"}
    """

    @Test func resultsContributeToApplicationsWithTheirVersions() throws {
        let items = try AppStoreUpdates.parse(updates)
        let source = UpdateSource(key: "mas", title: "App Store", command: "", state: .ok, items: items)
        let entries = ApplicationUpdatePresentation.entries(sources: [source], apps: [], query: "", sort: .name, lastOpened: [:])
        #expect(ApplicationUpdateSummary(sources: [source]).count == 2)
        #expect(entries.map(\.item.name) == ["Pages", "Xcode (Beta)"])
        #expect(entries.first?.sourceName == "App Store")
        #expect(entries.first?.versions?.current == "15.3")
        #expect(entries.first?.versions?.available == "15.4")
        #expect(entries.last?.versions?.available == "27.2")
    }

    @Test func emptySuccessfulResponseMeansNoUpdates() throws {
        #expect(try AppStoreUpdates.parse(" \n\n").isEmpty)
    }

    @Test(arguments: ["not JSON", "{\"name\":\"Pages\"}", "{\"name\":\"\",\"version\":\"1\",\"newVersion\":\"2\"}"])
    func malformedResponsesCannotMasqueradeAsUpToDate(_ output: String) {
        #expect(throws: DecodingError.self) { try AppStoreUpdates.parse(output) }
    }

    @Test func missingBundledToolDoesNotUseInstalledHomebrewTool() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("MacCare.app")
        #expect(AppStoreUpdates.executableURL(in: app) == nil)
        let result = AppStoreUpdates.check(bundleURL: app) { _, _ in
            Issue.record("No executable should be launched when the bundled component is missing")
            return .init(status: 0, stdout: "", stderr: "")
        }
        #expect(result.1 == .error("Le composant App Store est absent. Réinstallez MacCare."))
        #expect(result.2.isEmpty)
    }

    @Test func onlyBundledToolAndReadOnlyArgumentsAreUsed() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = app.appendingPathComponent("Contents/Helpers/mas")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let result = AppStoreUpdates.check(bundleURL: app) { path, arguments in
            #expect(path == executable.path)
            #expect(arguments == ["outdated", "--inaccurate", "--json"])
            return .init(status: 0, stdout: updates, stderr: "")
        }
        #expect(result.0 == "mas")
        #expect(result.1 == .ok)
        #expect(result.2.count == 2)
        let failed = AppStoreUpdates.check(bundleURL: app) { _, _ in
            .init(status: 1, stdout: updates, stderr: "Service failure")
        }
        #expect(failed.1 == .error("App Store indisponible. Réessayez la vérification."))
        #expect(failed.2.isEmpty)
        let malformed = AppStoreUpdates.check(bundleURL: app) { _, _ in
            .init(status: 0, stdout: "invalid", stderr: "")
        }
        #expect(malformed.1 == .error("Résultat App Store illisible. Réessayez la vérification."))
        #expect(malformed.2.isEmpty)
    }
}
