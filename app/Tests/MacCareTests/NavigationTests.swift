import XCTest
@testable import MacCare

final class NavigationTests: XCTestCase {
    func testEveryExistingModuleHasOneReachableDestination() {
        let destinations = NavigationSection.allCases.flatMap(\.destinations)
        XCTAssertEqual(destinations.count, Set(destinations).count, "Aucune fonction ne doit être dupliquée ou masquer une autre route")
        XCTAssertEqual(Set(destinations), Set(Module.allCases), "Aucun module existant ne doit disparaître de la navigation")
        for section in NavigationSection.allCases {
            for module in section.destinations { XCTAssertEqual(module.section, section) }
        }
        XCTAssertEqual(NavigationSection.primary.count, 9)
        XCTAssertEqual(NavigationSection.performance.defaultDestination, .performanceOverview)
    }

    func testAboutFollowsToolsAndHasItsOwnDestination() {
        XCTAssertEqual(Array(NavigationSection.primary.suffix(2)), [.tools, .about])
        XCTAssertEqual(NavigationSection.about.destinations, [.about])
        XCTAssertEqual(Module.about.section, .about)
        var history = NavigationHistory()
        history.remember(.about)
        XCTAssertEqual(history.destination(for: .about, developerTools: false), .about)
    }

    func testToolsEntryKeepsAllToolsReachable() {
        XCTAssertEqual(NavigationSection.tools.defaultDestination, .toolsOverview)
        XCTAssertEqual(Set(NavigationSection.tools.destinations), [.toolsOverview, .screenCleaning, .aiClutter, .applicationPermissions, .maintenance, .startup, .privacy, .diskHealth])
        XCTAssertEqual(Module.startup.section, .tools)
        XCTAssertEqual(Module.devJunk.section, .cleaning)
    }

    func testDeveloperSettingOnlyHidesDeveloperModules() {
        let enabled = Set(NavigationSection.allCases.flatMap { $0.destinations(developerTools: true) })
        let disabled = Set(NavigationSection.allCases.flatMap { $0.destinations(developerTools: false) })
        XCTAssertEqual(enabled.subtracting(disabled), [.devJunk, .simulators])
        XCTAssertTrue(disabled.contains(.systemClean))
        XCTAssertTrue(disabled.contains(.trash))
    }

    func testReturningToSectionPreservesLastDestinationAndDirectLinks() {
        var history = NavigationHistory()
        history.remember(.duplicates)
        history.remember(.startup)
        XCTAssertEqual(history.destination(for: .files, developerTools: true), .duplicates)
        XCTAssertEqual(history.destination(for: .tools, developerTools: true), .startup)
        XCTAssertEqual(history.destination(for: .cleaning, developerTools: true), .cleaningOverview)
        history.remember(.simulators)
        XCTAssertEqual(history.destination(for: .cleaning, developerTools: true), .simulators)
        XCTAssertEqual(history.destination(for: .cleaning, developerTools: false), .cleaningOverview)
    }
}
