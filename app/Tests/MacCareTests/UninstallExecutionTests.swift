import Combine
import XCTest
@testable import MacCare

@MainActor
final class UninstallExecutionTests: XCTestCase {
    func testSelectedApplicationInApplicationsCanBeUninstalled() async throws {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: "/Applications") else { throw XCTSkip("Dossier Applications non accessible en écriture") }
        let appURL = URL(fileURLWithPath: "/Applications/RemovalFixture-\(UUID().uuidString).app", isDirectory: true)
        try fm.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "org.example.removalfixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        defer {
            try? fm.removeItem(at: appURL)
            let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").appendingPathComponent(appURL.lastPathComponent)
            try? fm.removeItem(at: trash)
        }
        let model = UninstallModel()
        let scanned = expectation(description: "Application inspectée")
        let scan = model.$isScanning.dropFirst().filter { !$0 }.first().sink { _ in scanned.fulfill() }
        model.selectedApp = AppInfo(url: appURL, name: appURL.deletingPathExtension().lastPathComponent, bundleId: nil)
        await fulfillment(of: [scanned], timeout: 5)
        withExtendedLifetime(scan) {}
        XCTAssertEqual(model.residuals.count, 1)
        let finished = expectation(description: "Désinstallation terminée")
        let removed = model.$lastReport.compactMap { $0 }.first().sink { _ in finished.fulfill() }
        let rescanned = expectation(description: "État final inspecté")
        let rescan = model.$isScanning.dropFirst().filter { !$0 }.first().sink { _ in rescanned.fulfill() }
        model.cleanSelected()
        await fulfillment(of: [finished, rescanned], timeout: 5)
        withExtendedLifetime((removed, rescan)) {}
        let report = try XCTUnwrap(model.lastReport)
        XCTAssertEqual(report.removed, 1, "L’application choisie dans /Applications doit pouvoir être désinstallée")
        XCTAssertTrue(report.refused.isEmpty, "Refus actuel : \(report.refused)")
        XCTAssertFalse(fm.fileExists(atPath: appURL.path))
    }
}

extension UninstallExecutionTests {
    private func makeFixture(_ name: String = "") throws -> AppInfo {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: "/Applications") else { throw XCTSkip("Dossier Applications non accessible en écriture") }
        let url = URL(fileURLWithPath: "/Applications/RemovalFixture-\(UUID().uuidString)\(name).app", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return AppInfo(url: url, name: url.deletingPathExtension().lastPathComponent, bundleId: nil)
    }

    func testDirectUninstallHandlesQuotedNamesAndDoesNotAuthorizeASibling() throws {
        let fm = FileManager.default
        let app = try makeFixture(" \"\\ 🐈")
        let sibling = app.url.deletingLastPathComponent().appendingPathComponent("Other" + app.url.lastPathComponent)
        try fm.createDirectory(at: sibling, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: app.url); try? fm.removeItem(at: sibling) }
        let items = try Engine.inspectPaths([app.url.path, sibling.path])
        let report = try Remover.uninstall(items, app: app, direct: true)
        XCTAssertEqual(report.removed, 1)
        XCTAssertEqual(report.refused.map(\.path), [sibling.path])
        XCTAssertFalse(fm.fileExists(atPath: app.url.path))
        XCTAssertTrue(fm.fileExists(atPath: sibling.path))
    }

    func testApplicationDataCanBeRemovedWithoutRemovingTheUncheckedBundle() throws {
        let fm = FileManager.default
        let app = try makeFixture()
        let data = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/" + app.name)
        try Data([1, 2, 3]).write(to: data)
        defer { try? fm.removeItem(at: app.url); try? fm.removeItem(at: data) }
        let report = try Remover.uninstall(Engine.inspectPaths([data.path]), app: app, direct: true)
        XCTAssertEqual(report.removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: data.path))
        XCTAssertTrue(fm.fileExists(atPath: app.url.path))
    }

    func testTheCleaningEngineStillProtectsApplicationsAndReplacedBundlesAreRefused() throws {
        let fm = FileManager.default
        let app = try makeFixture()
        let moved = app.url.deletingLastPathComponent().appendingPathComponent("Kept" + app.url.lastPathComponent)
        defer { try? fm.removeItem(at: app.url); try? fm.removeItem(at: moved) }
        let items = try Engine.inspectPaths([app.url.path])
        let decisions = try Engine.planRemoval(.init(scope_root: "/Applications", items: items.map { .init(path: $0.path, identity: $0.identity) }))
        XCTAssertEqual(decisions.first?.refusal, "protected")
        try fm.moveItem(at: app.url, to: moved)
        try fm.createDirectory(at: app.url, withIntermediateDirectories: false)
        let report = try Remover.uninstall(items, app: app, direct: true)
        XCTAssertEqual(report.removed, 0)
        XCTAssertEqual(report.refused.first?.reason, "identity-changed")
        XCTAssertTrue(fm.fileExists(atPath: app.url.path))
    }
}
