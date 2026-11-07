import XCTest
@testable import MacCare

final class HomeCleaningBreakdownTests: XCTestCase {
    func testDistributionUsesTheSameSafeScopeAsTheHeroAndRetainsUnclassifiedData() {
        let breakdown = HomeCleaningBreakdown(groups: [
            group("user-cache", bytes: 7), group("container-cache", bytes: 3),
            group("user-logs", bytes: 2), group("system-temp", bytes: 4),
            group("future-category", bytes: 1), group("downloads-installers", bytes: 900, risk: .review)
        ])
        XCTAssertEqual(breakdown.total, 17)
        XCTAssertEqual(breakdown.parts.map(\.kind), [.caches, .temporary, .logs, .other])
        XCTAssertEqual(breakdown.parts.map(\.bytes), [10, 4, 2, 1])
        XCTAssertEqual(HomeCleaningBreakdown(stored: breakdown.stored, total: 17), breakdown)
    }

    func testHistoricalTotalsWithoutADistributionDoNotInventOne() {
        XCTAssertNil(HomeCleaningBreakdown(stored: nil, total: 42))
        XCTAssertNil(HomeCleaningBreakdown(stored: ["caches": 3], total: 42))
    }

    func testCorruptPersistenceCannotRenderFalseCountsOrAnOverflowingChart() {
        let invalid: [[String: Any]] = [
            ["caches": true], ["caches": -1], ["caches": 1.5], ["caches": "1"],
            ["unknown": 1], ["caches": NSNumber(value: UInt64.max), "logs": 1]
        ]
        for value in invalid { XCTAssertNil(HomeCleaningBreakdown(stored: value, total: 1)) }
    }

    func testAnEmptySuccessfulAnalysisHasNoFakeSegments() {
        let empty = HomeCleaningBreakdown(groups: [group("user-cache", bytes: 0)])
        XCTAssertTrue(empty.parts.isEmpty)
        XCTAssertEqual(empty.total, 0)
        XCTAssertEqual(HomeCleaningBreakdown(stored: empty.stored, total: 0), empty)
    }

    @MainActor
    func testAnotherVersionCannotAttachAnOldDistributionToANewerSummaryWithTheSameTotal() throws {
        let suite = testPreferencesSuite("MacCare.HomeCleaningHistory")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldDate = Date(timeIntervalSince1970: 1_000)
        defaults.set(oldDate, forKey: "lastSmartScanDate")
        defaults.set(NSNumber(value: 7), forKey: "lastSmartScanSafeBytes")
        defaults.set(["date": oldDate, "parts": ["caches": NSNumber(value: 7)]], forKey: "lastSmartScanSafeBreakdown")
        XCTAssertEqual(SmartScanModel(defaults: defaults).lastBreakdown?.total, 7)

        // Une copie plus ancienne peut écrire les clés historiques, sans connaître la répartition.
        defaults.set(Date(timeIntervalSince1970: 2_000), forKey: "lastSmartScanDate")
        XCTAssertNil(SmartScanModel(defaults: defaults).lastBreakdown)
    }

    private func group(_ category: String, bytes: UInt64, risk: RuleRisk = .safe) -> ScanGroup {
        let rule = CleaningCategory(id: category, title: category, summary: "", category: category,
                                    risk: risk, icon: "doc", root: "/tmp", usesThreshold: false,
                                    audience: .everyone, baseTOML: "")
        let item = ScanItem(id: category, path: "/tmp/fixture", category: category, size_bytes: bytes,
                            reason: "fixture", autoselect: risk == .safe,
                            identity: .init(device: 1, inode: 1), owner: nil)
        return ScanGroup(category: rule, items: [item])
    }
}
