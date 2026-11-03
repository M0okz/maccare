import XCTest
@testable import MacCare

final class CleaningOverviewTests: XCTestCase {
    func testCleaningEntryKeepsAllExistingToolsReachable() {
        XCTAssertEqual(NavigationSection.cleaning.defaultDestination, .cleaningOverview)
        XCTAssertEqual(Set(NavigationSection.cleaning.destinations),
                       [.cleaningOverview, .smartScan, .cleaning, .systemClean, .trash, .devJunk, .simulators])
        let hidden = Set(NavigationSection.cleaning.destinations(developerTools: true))
            .subtracting(NavigationSection.cleaning.destinations(developerTools: false))
        XCTAssertEqual(hidden, [.devJunk, .simulators])
    }

    func testStoppedOrIncompleteScanNeverClaimsNothingWasFound() {
        for flags in [(false, true), (false, false), (true, true)] {
            let summary = CleaningSummary(isComplete: flags.0, wasCancelled: flags.1, isCleaning: false, foundSize: 0)
            XCTAssertTrue(summary.isPartial)
            XCTAssertEqual(summary.title, "Résultats partiels")
            XCTAssertNotEqual(summary.title, "Aucun élément détecté")
        }
    }

    func testOnlyCompletedEmptyScanShowsEmptyResult() {
        let empty = CleaningSummary(isComplete: true, wasCancelled: false, isCleaning: false, foundSize: 0)
        XCTAssertFalse(empty.isPartial)
        XCTAssertEqual(empty.title, "Aucun élément détecté")
        let found = CleaningSummary(isComplete: true, wasCancelled: false, isCleaning: false, foundSize: 1024)
        XCTAssertTrue(found.title.contains("à examiner"))
        XCTAssertFalse(found.title.contains("libérés"))
    }

    func testActiveCleaningIsNeverPresentedAsCompletedResult() {
        let summary = CleaningSummary(isComplete: true, wasCancelled: false, isCleaning: true, foundSize: 0)
        XCTAssertEqual(summary.title, "Nettoyage en cours")
    }
}
