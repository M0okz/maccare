import XCTest
@testable import MacCare

final class ApplicationUpdatePresentationTests: XCTestCase {
    private func entry(_ detail: String) -> ApplicationUpdateEntry {
        ApplicationUpdateEntry(source: UpdateSource(key: "cask", title: "Apps", command: ""), item: OutdatedItem(name: "Example", detail: detail))
    }
    func testVersionsSupportExistingFeedBrewAndStoreFormats() {
        for detail in ["7.1.4 → 7.2.1", "(7.1.4) != 7.2.1", "(7.1.4 -> 7.2.1)"] {
            XCTAssertEqual(entry(detail).versions?.current, "7.1.4")
            XCTAssertEqual(entry(detail).versions?.available, "7.2.1")
        }
        XCTAssertNil(entry("Version inconnue").versions)
        XCTAssertNil(entry("7.1.4 →").versions)
    }
    func testApplicationScopeAndSourceIdentityStayDistinct() {
        let item = OutdatedItem(name: "Example", detail: "1 → 2")
        let sources = ["brew", "macos", "cask", "mas", "netnewswire"].map {
            UpdateSource(key: $0, title: $0, command: "", state: .ok, items: [item])
        }
        let entries = ApplicationUpdatePresentation.entries(sources: sources, apps: [], query: "", sort: .name, lastOpened: [:])
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
        XCTAssertEqual(Set(entries.map { $0.source.key }), ["cask", "mas", "netnewswire"])
    }
    func testRecentSortUsesKnownLastOpeningAndLeavesUnknownDatesLast() {
        let first = AppInfo(url: URL(fileURLWithPath: "/QA/Alpha.app"), name: "Alpha", bundleId: nil)
        let second = AppInfo(url: URL(fileURLWithPath: "/QA/Beta.app"), name: "Beta", bundleId: nil)
        let source = UpdateSource(key: "cask", title: "Apps", command: "", items: [OutdatedItem(name: "alpha", detail: "1 → 2"), OutdatedItem(name: "beta", detail: "1 → 2")])
        let entries = ApplicationUpdatePresentation.entries(sources: [source], apps: [first, second], query: "", sort: .recent, lastOpened: [second.url: Date(timeIntervalSince1970: 100)])
        XCTAssertEqual(entries.first?.item.name, "beta")
        XCTAssertEqual(entries.first?.applicationURL(in: [first, second]), second.url)
    }
    func testPublicationDateUnderstandsFeedTimestampAndPreservesUnknownInput() {
        let timestamp = "Tue, 20 Oct 2026 10:00:00 -0700"
        XCTAssertEqual(ApplicationUpdatePresentation.publicationDate(timestamp), ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z"))
        XCTAssertTrue(ApplicationUpdatePresentation.publicationLabel(timestamp).contains("2026"))
        XCTAssertEqual(ApplicationUpdatePresentation.publicationLabel("non communiquée"), "non communiquée")
    }
    func testNotesCollapseBlankLinesWithoutRemovingReleaseContent() {
        XCTAssertFalse(ApplicationUpdatePresentation.displayNotes(nil).isEmpty)
        XCTAssertEqual(ApplicationUpdatePresentation.displayNotes(" \n "), ApplicationUpdatePresentation.displayNotes(nil))
        XCTAssertEqual(ApplicationUpdatePresentation.notes("\nChanges:\n\n\n• Fixed bug\n\n\n• Added feature\n\n"), "Changes:\n• Fixed bug\n• Added feature")
    }
}
