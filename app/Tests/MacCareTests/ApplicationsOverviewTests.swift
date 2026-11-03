import XCTest
@testable import MacCare

final class ApplicationsOverviewTests: XCTestCase {
    func testApplicationsOverviewKeepsEveryExistingDestinationReachable() {
        XCTAssertEqual(NavigationSection.applications.defaultDestination, .applicationsOverview)
        XCTAssertEqual(Set(NavigationSection.applications.destinations), [.applicationsOverview, .uninstall, .updates])
        XCTAssertEqual(Module.applicationsOverview.section, .applications)
    }

    func testUpdateCountOnlyIncludesApplications() {
        let sources = [
            UpdateSource(key: "brew", title: "Tools", command: "", state: .ok, items: [OutdatedItem(name: "tool", detail: "")]),
            UpdateSource(key: "macos", title: "System", command: "", state: .ok, items: [OutdatedItem(name: "OS", detail: "")]),
            UpdateSource(key: "cask", title: "Apps", command: "", state: .ok, items: [OutdatedItem(name: "App", detail: "")]),
            UpdateSource(key: "mas", title: "Store", command: "", state: .notInstalled)
        ]
        let summary = ApplicationUpdateSummary(sources: sources)
        XCTAssertEqual(summary.count, 1)
        XCTAssertTrue(summary.available)
        XCTAssertEqual(summary.title, "1 mise à jour disponible")
    }

    func testUnavailableAndFailedSourcesNeverClaimAppsAreUpToDate() {
        for state: UpdateSource.State in [.notInstalled, .error("QA"), .checking] {
            let summary = ApplicationUpdateSummary(sources: [UpdateSource(key: "cask", title: "Apps", command: "", state: state)])
            XCTAssertFalse(summary.available)
            XCTAssertNotEqual(summary.title, "Aucune mise à jour détectée")
        }
    }

    func testPartialCheckExplicitlyMarksCountAsMinimum() {
        let summary = ApplicationUpdateSummary(sources: [
            UpdateSource(key: "cask", title: "Apps", command: "", state: .ok, items: [OutdatedItem(name: "App", detail: "")]),
            UpdateSource(key: "mas", title: "Store", command: "", state: .error("QA"))
        ])
        XCTAssertTrue(summary.hasErrors)
        XCTAssertEqual(summary.title, "Au moins 1 mise à jour disponible")
    }
}
