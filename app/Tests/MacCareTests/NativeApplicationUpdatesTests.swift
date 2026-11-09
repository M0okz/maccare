import XCTest
@testable import MacCare

final class NativeApplicationUpdatesTests: XCTestCase {
    private let environment = HomebrewApplicationCatalog.Environment(systemVersion: "15.1.0", platform: "arm64_sequoia")
    private func app(_ id: String = "org.example.Editor", name: String = "Editor", version: String = "1.0", store: Bool = false) -> InstalledUpdateApplication {
        .init(url: URL(fileURLWithPath: "/QA/\(name).app"), name: name, bundleID: id, version: version, appStore: store)
    }
    private func cask(_ changes: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["token": "editor", "version": "2.0,200", "homepage": "https://example.org/editor",
            "supported_platforms": ["arm64_sequoia"],
            "artifacts": [["app": ["Editor.app"]], ["uninstall": [["quit": "org.example.Editor"]]]]]
        value.merge(changes) { _, new in new }; return value
    }
    private func data(_ casks: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: casks) }
    private func updates(_ casks: [[String: Any]], apps: [InstalledUpdateApplication]? = nil) throws -> [OutdatedItem] {
        try HomebrewApplicationCatalog.updates(data: data(casks), apps: apps ?? [app()], environment: environment)
    }
    private func release(_ changes: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["tag_name": "v0.16.1", "draft": false, "prerelease": false,
            "body": "Fixes", "published_at": "2026-11-08T01:49:38Z",
            "assets": [["name": "artcraft-launcher-0.16.1-macos-universal.dmg", "size": 1234]]]
        value.merge(changes) { _, new in new }; return try JSONSerialization.data(withJSONObject: value)
    }

    func testCatalogRecognizesDirectInstallWithoutBrewAndUsesEditorWebsite() throws {
        let result = try updates([cask()])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.detail, "1.0 → 2.0")
        XCTAssertEqual(result.first?.applicationURL, app().url)
        XCTAssertEqual(result.first?.downloadURL?.absoluteString, "https://example.org/editor")
        XCTAssertEqual(result.first?.catalogToken, "editor")
    }
    func testBothIdentityAndAppArtifactAreRequired() throws {
        XCTAssertTrue(try updates([cask()], apps: [app("org.other.Editor")]).isEmpty)
        XCTAssertTrue(try updates([cask()], apps: [app(name: "Another")]).isEmpty)
        XCTAssertTrue(try updates([cask(["artifacts": [["uninstall": [["quit": "org.example.Editor"]]]]])]).isEmpty)
    }
    func testExactPreferenceIdentifierSupportsAppsWithoutQuitRule() throws {
        let artifacts: [[String: Any]] = [["app": ["Editor.app"]], ["zap": [["trash": ["~/Library/Preferences/org.example.Editor.plist"]]]]]
        XCTAssertEqual(try updates([cask(["artifacts": artifacts])]).count, 1)
        let wildcard: [[String: Any]] = [["app": ["Editor.app"]], ["zap": [["trash": ["~/Library/Preferences/org.example.*.plist"]]]]]
        XCTAssertTrue(try updates([cask(["artifacts": wildcard])]).isEmpty)
    }
    func testStorePrereleaseDisabledAndAmbiguousEditionsAreSkipped() throws {
        XCTAssertTrue(try updates([cask()], apps: [app(store: true)]).isEmpty)
        for change: [String: Any] in [["token": "editor@beta"], ["version": "latest"], ["version": "2.0-rc1"], ["disabled": true], ["deprecated": true]] {
            XCTAssertTrue(try updates([cask(change)]).isEmpty)
        }
        XCTAssertTrue(try updates([cask(), cask(["token": "editor-vfs"])]).isEmpty)
    }
    func testSystemAndArchitectureCompatibilityAndVersionVariation() throws {
        XCTAssertTrue(try updates([cask(["supported_platforms": ["sequoia"]])]).isEmpty)
        XCTAssertTrue(try updates([cask(["depends_on": ["macos": [">=": ["26"]]]])]).isEmpty)
        XCTAssertTrue(try updates([cask(["depends_on": ["macos": ["==": ["14"]]]])]).isEmpty)
        let variation: [String: Any] = ["arm64_sequoia": ["version": "1.0"]]
        XCTAssertTrue(try updates([cask(["variations": variation])]).isEmpty)
    }
    func testVersionOrderingDoesNotSuggestDowngradeOrNormalizeAwayReleaseIdentity() {
        for (installed, available) in [("2.0", "1.9"), ("2.0.0", "2.0"), ("2.0-beta", "2.1"), ("unknown", "2.1"), ("1.0", "2..1")] {
            XCTAssertFalse(ApplicationReleaseVersion.isNewer(available, than: installed))
        }
        XCTAssertTrue(ApplicationReleaseVersion.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(ApplicationReleaseVersion.isNewer("v0.16.1", than: "0.16.0"))
    }
    func testArtCraftStableOfficialReleaseOnlyAndNoRemoteDestinationTrust() throws {
        let source = OfficialGitHubApplication.catalog[0]
        let craft = app(source.bundleID, name: "Renamed Craft", version: "0.15.0")
        let result = try source.updates(data: release(["html_url": "https://unrelated.invalid"]), apps: [craft])
        XCTAssertEqual(result.first?.detail, "0.15.0 → 0.16.1")
        XCTAssertEqual(result.first?.downloadURL?.absoluteString, "https://github.com/storytold/craft-launcher/releases/tag/v0.16.1")
        XCTAssertEqual(result.first?.downloadBytes, 1234)
        for change: [String: Any] in [["prerelease": true], ["draft": true], ["tag_name": "v0.17.0-beta"], ["assets": []]] {
            XCTAssertTrue(try source.updates(data: release(change), apps: [craft]).isEmpty)
        }
        XCTAssertTrue(try source.updates(data: release(), apps: [app("org.other.craft")]).isEmpty)
    }
    func testFailureKeepsSuccessfulResultsAndDoesNotClaimCompleteCheck() async throws {
        let source = OfficialGitHubApplication.catalog[0]
        let craft = app(source.bundleID, name: "ArtCraft Launcher", version: "0.15.0")
        let payload = try release()
        let result = await NativeApplicationUpdates.check(apps: [craft]) { url, _ in
            if url == source.apiURL { return payload }
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(result.2.count, 1)
        guard case .error = result.1 else { return XCTFail("Partial check must report an error") }
        let summary = ApplicationUpdateSummary(sources: [UpdateSource(key: result.0, title: "Catalog", command: "", state: result.1, items: result.2)])
        XCTAssertEqual(summary.title, "Au moins 1 mise à jour disponible")
    }
    func testNoNetworkWhenOnlyAppStoreAppsAreInstalled() async {
        let result = await NativeApplicationUpdates.check(apps: [app(store: true)]) { _, _ in
            XCTFail("Store installations must not query the catalog"); throw URLError(.badURL)
        }
        XCTAssertEqual(result.1, .notInstalled)
    }
    func testCatalogAndOfficialFeedDoNotDuplicateBrewResults() {
        let url = app().url
        let sources = [UpdateSource(key: "cask", title: "Brew", command: "", state: .ok, items: [.init(name: "editor", detail: "1 → 2")]),
                       UpdateSource(key: "catalog", title: "Catalog", command: "", state: .ok, items: [.init(name: "Editor", detail: "1 → 2", applicationURL: url, catalogToken: "editor")]),
                       UpdateSource(key: "netnewswire", title: "Official", command: "", state: .ok, items: [.init(name: "Editor", detail: "1 → 2", applicationURL: url)])]
        let result = UpdatesModel.removingCatalogDuplicates(sources)
        XCTAssertEqual(result.reduce(0) { $0 + $1.items.count }, 1)
        XCTAssertEqual(ApplicationUpdatePresentation.entries(sources: result, apps: [], query: "", sort: .name, lastOpened: [:]).count, 1)
    }
    func testLiveOfficialSourcesWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["MACCARE_UPDATE_NETWORK_QA"] == "1" else { throw XCTSkip("Opt-in live network QA") }
        let craft = app(OfficialGitHubApplication.catalog[0].bundleID, name: "ArtCraft Launcher", version: "0.1.0")
        let cursor = app("com.todesktop.230313mzl4w4u92", name: "Cursor", version: "1.0")
        let result = await NativeApplicationUpdates.check(apps: [craft, cursor])
        XCTAssertEqual(result.1, .ok)
        XCTAssertEqual(Set(result.2.map(\.name)), ["ArtCraft Launcher", "Cursor"])
        print("LIVE_UPDATE_QA", result.2.map { "\($0.name): \($0.detail)" })
        let actual = await NativeApplicationUpdates.check()
        XCTAssertEqual(actual.1, .ok)
        print("LIVE_INSTALLED_QA", actual.2.map { "\($0.name): \($0.detail)" })
    }
}
