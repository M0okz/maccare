import XCTest
@testable import MacCare

final class NetNewsWireUpdatesTests: XCTestCase {
    func testNotesIncludeOnlyCompatibleVersionsBetweenInstalledAndTarget() {
        func release(_ version: String, _ build: String, _ system: String = "14.0") -> NetNewsWireRelease {
            NetNewsWireRelease(version: version, build: build, minimumSystem: system, date: "", bytes: 1, notes: "Notes \(version)")
        }
        let notes = NetNewsWireFeed.notesSince([release("7.2", "720"), release("7.1.4", "714"), release("7.2.1", "721"), release("8.0", "800", "99.0")], installedBuild: "714", throughBuild: "721", systemVersion: "26.0")
        XCTAssertEqual(notes, "Version 7.2.1\nNotes 7.2.1\n\nVersion 7.2\nNotes 7.2")
        XCTAssertFalse(notes.contains("7.1.4"))
        XCTAssertFalse(notes.contains("8.0"))
    }

    func testStableFeedVersionsAndNotes() throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <description><![CDATA[Changes:<ul><li>Fixed sidebar</li></ul>]]></description>
        <pubDate>20 Oct 2026</pubDate>
        <enclosure sparkle:version="7224" sparkle:shortVersionString="7.2.1" length="10002485"/>
        <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
        </item></channel></rss>
        """
        let releases = try NetNewsWireFeed.parse(Data(xml.utf8))
        let release = try XCTUnwrap(NetNewsWireFeed.latest(releases, installedBuild: "7100", systemVersion: "26.0"))
        XCTAssertEqual(release.version, "7.2.1")
        XCTAssertEqual(release.bytes, 10002485)
        XCTAssertTrue(release.notes.contains("• Fixed sidebar"))
        XCTAssertFalse(release.notes.contains("<li>"))
        XCTAssertNil(NetNewsWireFeed.latest(releases, installedBuild: "7224", systemVersion: "26.0"))
        XCTAssertNil(NetNewsWireFeed.latest(releases, installedBuild: "7100", systemVersion: "14.0"))
    }

    func testSparkleContributesToApplicationSummary() {
        let source = UpdateSource(key: "netnewswire", title: "Sparkle", command: "", state: .ok,
                                  items: [.init(name: "NetNewsWire", detail: "7.1.4 → 7.2.1")])
        XCTAssertEqual(ApplicationUpdateSummary(sources: [source]).count, 1)
    }

    func testMalformedFeedFails() {
        XCTAssertThrowsError(try NetNewsWireFeed.parse(Data("<rss><item>".utf8)))
    }
}
