import XCTest
import MacCareMaintenance
@testable import MacCare

final class PerformancePresentationTests: XCTestCase {
    private func unavailable(_ task: PerformanceTask, helper: Bool = true, disk: Bool = true, mail: Bool = false,
                             preparing: Bool = false, count: Int? = 1, error: String? = nil) -> String? {
        PerformanceTaskPresentation.unavailable(task, helperEnabled: helper, fullDiskGranted: disk, mailRunning: mail,
                                               preparing: preparing, cacheCount: count, cacheError: error)
    }
    func testMailRequiresReadAccessAndAClosedApplication() {
        XCTAssertNotNil(unavailable(.mail, disk: false))
        XCTAssertNotNil(unavailable(.mail, mail: true))
        XCTAssertNil(unavailable(.mail))
    }
    func testOnlyPrivilegedTasksDependOnHelper() {
        for task in [PerformanceTask.spotlight, .permissions, .dns] {
            XCTAssertNotNil(unavailable(task, helper: false))
            XCTAssertNil(unavailable(task))
        }
        XCTAssertNil(unavailable(.mail, helper: false))
        XCTAssertNil(unavailable(.purgeable, helper: false))
    }
    func testCachesNeedACompletedNonEmptyPlanAndPreserveFailureReason() {
        XCTAssertNotNil(unavailable(.purgeable, preparing: true))
        XCTAssertNotNil(unavailable(.purgeable, count: nil))
        XCTAssertNotNil(unavailable(.purgeable, count: 0))
        XCTAssertEqual(unavailable(.purgeable, error: "Lecture QA impossible"), "Lecture QA impossible")
        XCTAssertNil(unavailable(.purgeable, count: 3))
    }
    func testPresentationNamesDescribeRealScope() {
        XCTAssertTrue(PerformanceTaskPresentation.title(.permissions).contains("compte"))
        XCTAssertTrue(PerformanceTaskPresentation.title(.purgeable).contains("purgeable"))
        XCTAssertFalse(PerformanceTaskPresentation.title(.mail).contains("Accélérer"))
    }
}
