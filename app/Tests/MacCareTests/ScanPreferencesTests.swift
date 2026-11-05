import XCTest
@testable import MacCare

final class ScanPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var safe: CleaningCategory!
    private var review: CleaningCategory!
    private var developer: CleaningCategory!

    override func setUp() {
        suite = testPreferencesSuite("MacCare.ScanPreferencesTests")
        defaults = UserDefaults(suiteName: suite)!
        safe = category("cache.test", risk: .safe)
        review = category("ios.test", risk: .review)
        developer = category("xcode.test", risk: .safe, audience: .developer)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDefaultAndThoroughHaveDifferentScopeWithoutChangingRisk() {
        let preferences = ScanPreferences(defaults: defaults)
        XCTAssertEqual(preferences.profile, .recommended)
        XCTAssertEqual(preferences.categories(from: [safe, review]).map(\.id), [safe.id])
        preferences.select(.thorough)
        XCTAssertEqual(preferences.categories(from: [safe, review]).map(\.id), [safe.id, review.id])
        XCTAssertEqual(review.risk, .review)
        XCTAssertEqual(ScanPreferences(defaults: defaults).profile, .thorough)
    }

    func testEditingPresetSeedsCustomSelectionAndPersistsEmptyChoice() {
        let preferences = ScanPreferences(defaults: defaults)
        preferences.set([review], enabled: true, available: [safe, review])
        XCTAssertEqual(preferences.profile, .custom)
        XCTAssertEqual(preferences.customIDs, [safe.id, review.id])
        preferences.set([safe, review], enabled: false, available: [safe, review])
        let reloaded = ScanPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.profile, .custom)
        XCTAssertTrue(reloaded.categories(from: [safe, review]).isEmpty)
    }

    func testPresetRoundTripPreservesCustomChoiceAndDeveloperGate() {
        let preferences = ScanPreferences(defaults: defaults)
        preferences.set([developer], enabled: true, available: [safe, developer, review])
        preferences.select(.thorough)
        XCTAssertFalse(preferences.categories(from: [safe, review]).contains(developer))
        preferences.select(.custom)
        XCTAssertEqual(Set(preferences.categories(from: [safe, developer, review]).map(\.id)), [safe.id, developer.id])
        XCTAssertEqual(preferences.categories(from: [safe, review]).map(\.id), [safe.id])
    }

    func testNewCategoriesAreNotSilentlyAddedToCustomSelection() {
        let preferences = ScanPreferences(defaults: defaults)
        preferences.set([safe], enabled: true, available: [safe])
        XCTAssertEqual(preferences.categories(from: [safe, review, developer]).map(\.id), [safe.id])
    }

    @MainActor
    func testEmptyScopeDoesNotStartOrCompleteAScan() {
        let model = SmartScanModel(categories: { [] })
        let previousCompletion = model.lastCompletedAt
        model.scan()
        XCTAssertEqual(model.stage, .idle)
        XCTAssertFalse(model.isComplete)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNotNil(model.statusMessage)
        XCTAssertEqual(model.lastCompletedAt, previousCompletion)
    }

    private func category(_ id: String, risk: RuleRisk, audience: RuleAudience = .everyone) -> CleaningCategory {
        CleaningCategory(id: id, title: id, summary: "Test", category: id, risk: risk,
                         icon: "folder", root: "/unused-test-fixture", usesThreshold: false,
                         audience: audience, baseTOML: "")
    }
}
