import XCTest
@testable import MacCare

/// Explicit gates prove overlap without assuming a network speed or relying on sleeps.
private actor UpdateCheckGate {
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    private var released = Set<String>()

    func wait(_ key: String) async {
        if released.contains(key) { return }
        await withCheckedContinuation { waiting[key] = $0 }
    }

    func release(_ key: String) {
        released.insert(key)
        waiting.removeValue(forKey: key)?.resume()
    }
}

final class ConcurrentUpdateChecksTests: XCTestCase {
    @MainActor
    func testAllProvidersStartBeforeAnyFinishesAndEveryCompletionPublishes() async {
        let gate = UpdateCheckGate()
        let started = expectation(description: "All providers started")
        started.expectedFulfillmentCount = 3
        let catalogDone = expectation(description: "Catalog published before others finish")
        let officialDone = expectation(description: "Official published before CLI finishes")
        let appURL = URL(fileURLWithPath: "/QA/Editor.app")
        let definitions = ["cask", "catalog", "netnewswire"].map { UpdateSource(key: $0, title: $0, command: "") }
        var snapshots: [[UpdateSource]] = []
        let scan = Task {
            await UpdatesModel.checkConcurrently(sources: definitions, using: { key in
                started.fulfill()
                await gate.wait(key)
                switch key {
                case "cask": return (key, .ok, [.init(name: "editor", detail: "1 → 2")])
                case "catalog": return (key, .ok, [.init(name: "Editor", detail: "1 → 2", applicationURL: appURL, catalogToken: "editor")])
                default: return (key, .ok, [.init(name: "Editor", detail: "1 → 2", applicationURL: appURL)])
                }
            }, didUpdate: { sources in
                snapshots.append(sources)
                if snapshots.count == 1 { catalogDone.fulfill() }
                if snapshots.count == 2 { officialDone.fulfill() }
            })
        }
        await fulfillment(of: [started], timeout: 3)
        await gate.release("catalog")
        await fulfillment(of: [catalogDone], timeout: 3)
        XCTAssertEqual(snapshots.first?.map(\.state), [.checking, .ok, .checking])
        await gate.release("netnewswire")
        await fulfillment(of: [officialDone], timeout: 3)
        XCTAssertEqual(snapshots.last?.map(\.state), [.checking, .ok, .ok])
        await gate.release("cask")
        await scan.value
        XCTAssertEqual(snapshots.count, 3)
        let final = snapshots.last ?? []
        XCTAssertEqual(final.map(\.key), ["cask", "catalog", "netnewswire"])
        // The catalog row was hidden by the official feed before the CLI finished.
        // Its original token must still suppress the later CLI duplicate.
        XCTAssertEqual(final.map { $0.items.count }, [0, 0, 1])
    }

    @MainActor
    func testFailedProviderDoesNotDiscardOtherResults() async {
        var snapshots: [[UpdateSource]] = []
        await UpdatesModel.checkConcurrently(sources: ["mas", "catalog"].map { UpdateSource(key: $0, title: $0, command: "") }, using: { key in
            key == "mas" ? (key, .error("Offline"), []) : (key, .ok, [.init(name: "Editor", detail: "1 → 2")])
        }, didUpdate: { snapshots.append($0) })
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.last?.first?.state, .error("Offline"))
        XCTAssertEqual(snapshots.last?.last?.items.count, 1)
    }

    func testCatalogAndOfficialGitHubRequestsOverlap() async throws {
        let source = OfficialGitHubApplication.catalog[0]
        let app = InstalledUpdateApplication(url: URL(fileURLWithPath: "/QA/ArtCraft Launcher.app"), name: "ArtCraft Launcher", bundleID: source.bundleID, version: "0.1.0", appStore: false)
        let release = Data(#"{"tag_name":"v0.16.1","draft":false,"prerelease":false,"assets":[{"name":"artcraft-launcher-0.16.1-macos-universal.dmg","size":1234}]}"#.utf8)
        let gate = UpdateCheckGate()
        let started = expectation(description: "Both HTTP requests started")
        started.expectedFulfillmentCount = 2
        let scan = Task {
            await NativeApplicationUpdates.check(apps: [app]) { url, _ in
                started.fulfill()
                await gate.wait(url.absoluteString)
                return url == source.apiURL ? release : Data("[{}]".utf8)
            }
        }
        await fulfillment(of: [started], timeout: 3)
        await gate.release(source.apiURL.absoluteString)
        await gate.release(NativeApplicationUpdates.catalogURL.absoluteString)
        let result = await scan.value
        XCTAssertEqual(result.1, .ok)
        XCTAssertEqual(result.2.map(\.name), ["ArtCraft Launcher"])
    }
    func testFailedOfficialFeedDoesNotFallBackToCompetingCatalogVersion() async throws {
        let source = OfficialGitHubApplication.catalog[0]
        let app = InstalledUpdateApplication(url: URL(fileURLWithPath: "/QA/ArtCraft Launcher.app"), name: "ArtCraft Launcher", bundleID: source.bundleID, version: "0.1.0", appStore: false)
        let catalog = try JSONSerialization.data(withJSONObject: [[
            "token": "artcraft-launcher", "version": "999.0", "homepage": "https://example.org",
            "supported_platforms": [HomebrewApplicationCatalog.Environment.current.platform],
            "artifacts": [["app": ["ArtCraft Launcher.app"]], ["uninstall": [["quit": source.bundleID]]]]
        ]])
        let result = await NativeApplicationUpdates.check(apps: [app]) { url, _ in
            if url == source.apiURL { throw URLError(.notConnectedToInternet) }
            return catalog
        }
        guard case .error = result.1 else { return XCTFail("The failed official feed must be reported") }
        XCTAssertTrue(result.2.isEmpty, "An official provider keeps precedence even on failure")
    }

}
