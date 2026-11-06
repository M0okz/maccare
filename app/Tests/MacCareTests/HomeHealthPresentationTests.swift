import XCTest
import MacCareBattery
@testable import MacCare

final class HomeHealthPresentationTests: XCTestCase {
    private let healthyDisk = TrayStorageUsage(free: 100_000_000_000, total: 500_000_000_000)

    func testHealthyDesktopHasAnHonestSummaryAndTheExistingScore() {
        let result = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal,
                                            battery: .init(present: false))
        XCTAssertEqual(result.state, .healthy)
        XCTAssertEqual(result.title, "Tout va bien")
        XCTAssertEqual(result.assessment.percent, 100)
    }

    func testStorageWarningUsesTheExistingLowSpacePolicyWithoutChangingTheScore() {
        let disk = TrayStorageUsage(free: 28_000_000_000, total: 500_000_000_000)
        let battery = BatterySnapshot(healthPercent: 100)
        let result = HomeHealthPresentation(storage: disk, pressure: .normal, thermal: .nominal, battery: battery)
        XCTAssertEqual(result.state, .watch)
        XCTAssertEqual(result.detail, "Stockage presque plein")
        XCTAssertEqual(result.assessment.percent,
                       MacHealthScore.assess(free: disk?.available, total: disk?.total, pressure: .normal,
                                             thermal: .nominal, battery: battery).percent)
    }

    func testCriticalMemoryIsNeverHiddenByAnOrdinaryStorageWarning() {
        let result = HomeHealthPresentation(storage: .init(free: 28_000_000_000, total: 500_000_000_000),
                                            pressure: .critical, thermal: .nominal, battery: .init(present: false))
        XCTAssertEqual(result.state, .check)
        XCTAssertEqual(result.detail, "Pression mémoire critique")
        XCTAssertEqual(result.assessment.grade, .poor)
    }

    func testMissingMeasurementsCannotClaimEverythingIsHealthy() {
        let pending = HomeHealthPresentation(storage: nil, pressure: nil, thermal: .nominal, battery: nil)
        XCTAssertEqual(pending.state, .reading)
        XCTAssertNil(pending.assessment.percent)
        let partial = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal, battery: nil)
        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.assessment.grade, .good)
    }

    func testMemoryWarningAndBatteryCapacityRemainDistinctFromChargeLevel() {
        let memory = HomeHealthPresentation(storage: healthyDisk, pressure: .warning, thermal: .nominal,
                                            battery: .init(percent: 100, healthPercent: 100))
        XCTAssertEqual(memory.state, .watch)
        XCTAssertEqual(memory.detail, "Pression mémoire élevée")
        let lowCharge = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal,
                                               battery: .init(percent: 5, healthPercent: 100))
        XCTAssertEqual(lowCharge.state, .healthy)
        let worn = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal,
                                           battery: .init(percent: 100, healthPercent: 75))
        XCTAssertEqual(worn.state, .watch)
        XCTAssertEqual(worn.detail, "Capacité de la batterie réduite")
    }

    func testThermalAndBatteryFaultsHavePriority() {
        let hot = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .serious,
                                         battery: .init(present: false))
        XCTAssertEqual(hot.state, .check)
        XCTAssertEqual(hot.detail, "État thermique élevé")
        let fault = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal,
                                           battery: .init(healthPercent: 100, batteryFault: true))
        XCTAssertEqual(fault.state, .check)
        XCTAssertEqual(fault.detail, "Batterie à vérifier")
    }

    func testAPoorBatteryAssessmentTakesPriorityOverALowStorageWarning() {
        let result = HomeHealthPresentation(storage: .init(free: 28_000_000_000, total: 500_000_000_000),
                                            pressure: .normal, thermal: .nominal, battery: .init(healthPercent: 40))
        XCTAssertEqual(result.assessment.grade, .poor)
        XCTAssertEqual(result.state, .check)
        XCTAssertTrue(result.detail.contains("batterie"))
    }

    func testTheOverviewNeverLeaksScoreCeilingsIntoItsShortReason() {
        for battery in [nil, BatterySnapshot(), BatterySnapshot(healthPercent: 40)] {
            let result = HomeHealthPresentation(storage: healthyDisk, pressure: .normal, thermal: .nominal, battery: battery)
            XCTAssertFalse(result.detail.contains("%"))
            XCTAssertFalse(result.detail.contains("indice"))
            XCTAssertFalse(result.detail.contains("plafonn"))
        }
    }
}
