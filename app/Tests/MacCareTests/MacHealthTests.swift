import XCTest
import MacCareBattery
@testable import MacCare

final class MacHealthTests: XCTestCase {
    private func assess(free: UInt64? = 100_000_000_000, total: UInt64? = 500_000_000_000,
                        pressure: MemoryPressureLevel? = .normal, thermal: ProcessInfo.ThermalState = .nominal,
                        battery: BatterySnapshot? = .init(present: false)) -> MacHealthScore.Assessment {
        MacHealthScore.assess(free: free, total: total, pressure: pressure, thermal: thermal, battery: battery)
    }

    func testHealthyDesktopHasNoBatteryPenalty() {
        let result = assess()
        XCTAssertEqual(result.percent, 100)
        XCTAssertEqual(result.grade, .excellent)
        XCTAssertEqual(result.components.count, 3)
    }

    func testChargePercentageDoesNotDetermineBatteryHealth() {
        let low = BatterySnapshot(percent: 5, healthPercent: 100)
        let full = BatterySnapshot(percent: 100, healthPercent: 100)
        XCTAssertEqual(assess(battery: low).percent, assess(battery: full).percent)
        XCTAssertEqual(assess(battery: low).percent, 100)
    }

    func testCriticalConditionsCannotBeHiddenByOtherHealthyComponents() {
        XCTAssertLessThan(assess(pressure: .critical).percent ?? 100, 50)
        XCTAssertLessThan(assess(thermal: .serious).percent ?? 100, 50)
        XCTAssertLessThan(assess(thermal: .critical).percent ?? 100, 50)
        XCTAssertLessThan(assess(free: 1_000_000_000).percent ?? 100, 50)
        XCTAssertLessThan(assess(battery: .init(healthPercent: 100, batteryFault: true)).percent ?? 100, 50)
        XCTAssertLessThan(assess(battery: .init(healthPercent: 30)).percent ?? 100, 50)
    }

    func testMissingMeasurementsNeverProduceAnExcellentHealthClaim() {
        XCTAssertNil(assess(pressure: nil).percent)
        XCTAssertNil(assess(total: 0).percent)
        XCTAssertNil(assess(free: nil).percent)
        XCTAssertEqual(assess(battery: nil).grade, .good)
        XCTAssertEqual(assess(battery: .init()).grade, .good)
        var battery = BatterySnapshot()
        battery.healthState = "Poor"
        XCTAssertEqual(assess(battery: battery).grade, .poor)
    }

    func testStorageScoreImprovesMonotonicallyAndStopsAtItsReserve() throws {
        let scores = try [0, 1, 5, 10, 25, 50, 100].map { free in
            try XCTUnwrap(assess(free: UInt64(free) * 1_000_000_000).percent)
        }
        XCTAssertEqual(scores, scores.sorted())
        XCTAssertEqual(scores.suffix(2).first, scores.last)
        XCTAssertTrue(scores.allSatisfy { (0...100).contains($0) })
    }

    func testGradeThresholdsAreExplicit() {
        XCTAssertEqual(MacHealthScore.Assessment(percent: 49, components: [], notes: []).grade, .poor)
        XCTAssertEqual(MacHealthScore.Assessment(percent: 50, components: [], notes: []).grade, .good)
        XCTAssertEqual(MacHealthScore.Assessment(percent: 84, components: [], notes: []).grade, .good)
        XCTAssertEqual(MacHealthScore.Assessment(percent: 85, components: [], notes: []).grade, .excellent)
    }

    func testUptimeFormattingHandlesClockChangesAndLongDurations() {
        XCTAssertEqual(MacSystemSpecs.duration(-1), "—")
        XCTAssertEqual(MacSystemSpecs.duration(.nan), "—")
        XCTAssertEqual(MacSystemSpecs.duration(30), "moins d’une minute")
        XCTAssertEqual(MacSystemSpecs.duration(3660), "1 h 1 min")
        XCTAssertEqual(MacSystemSpecs.duration(2 * 86400 + 3 * 3600), "2 j 3 h")
    }
}
