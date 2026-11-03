import XCTest
@testable import MacCare

final class ToolsDetailsTests: XCTestCase {
    private func item(_ path: String, bytes: UInt64 = 100) -> ScanItem {
        ScanItem(id: path, path: path, category: "privacy", size_bytes: bytes, reason: "QA", autoselect: false, identity: FileIdentity(device: 1, inode: 1), owner: nil)
    }

    func testPrivacyGroupsKeepEveryCatalogEntryInExactlyOneCategory() {
        for entry in PrivacyCatalog.entries {
            let candidate = item(entry.path)
            XCTAssertEqual(PrivacyGroup.allCases.filter { $0.contains(candidate) }.count, 1)
            if ["QuickLook", "Système", "Rapports"].contains(entry.tag) {
                XCTAssertTrue(PrivacyGroup.local.contains(candidate))
            } else {
                XCTAssertTrue(PrivacyGroup.browsers.contains(candidate))
            }
        }
        XCTAssertTrue(PrivacyGroup.local.contains(item("/QA/unknown")))
    }

    @MainActor func testPrivacyScanUsesReadOnlyFixtureAndStartsWithNoSelection() async throws {
        let sample = item("/QA/cache")
        let empty = item("/QA/empty", bytes: 0)
        let model = PrivacyModel(inspect: { _ in [sample, empty] })
        XCTAssertFalse(model.hasScanned)
        XCTAssertFalse(model.isScanning)
        model.scan()
        try await finish(model)
        XCTAssertEqual(model.items.map(\.path), [sample.path])
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertFalse(model.scanFailed)
        model.selectAll()
        XCTAssertEqual(model.selectedSize, 100)
        model.scan()
        try await finish(model)
        XCTAssertTrue(model.selection.isEmpty)
    }

    @MainActor func testPrivacyFailureIsDistinctFromEmptySuccess() async throws {
        let model = PrivacyModel(inspect: { _ in throw NSError(domain: "QA", code: 1) })
        model.scan()
        try await finish(model)
        XCTAssertTrue(model.hasScanned)
        XCTAssertTrue(model.scanFailed)
        XCTAssertNotNil(model.statusMessage)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testStartupSearchTrimsWhitespaceAndMatchesAccentsNamesAndPaths() {
        XCTAssertTrue(StartupFilter.matches("  ", values: []))
        XCTAssertTrue(StartupFilter.matches(" REVEIL ", values: ["Réveil", "/QA/agent"]))
        XCTAssertTrue(StartupFilter.matches("/qa/AGENT", values: ["Service", "/QA/agent"]))
        XCTAssertFalse(StartupFilter.matches("absent", values: ["Service", "/QA/agent"]))
    }

    @MainActor private func finish(_ model: PrivacyModel) async throws {
        for _ in 0..<200 {
            if !model.isScanning { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("L’analyse injectée ne se termine pas")
    }
}
