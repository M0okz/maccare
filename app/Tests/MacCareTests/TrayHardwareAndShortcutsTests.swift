import XCTest
@testable import MacCare

final class TrayHardwareAndShortcutsTests: XCTestCase {
    func testGPUUnavailableIsDifferentFromIdleAndInvalidValuesAreRejected() {
        XCTAssertNil(TrayGPU.utilization(nil))
        XCTAssertNil(TrayGPU.utilization(true))
        XCTAssertNil(TrayGPU.utilization(-1))
        XCTAssertNil(TrayGPU.utilization(101))
        XCTAssertNil(TrayGPU.utilization(Double.nan))
        XCTAssertEqual(TrayGPU.utilization(0), 0)
        XCTAssertEqual(TrayGPU.utilization(37), 0.37)
    }
    func testFanStoppedMissingAndAbsentRemainDistinct() {
        let stopped = TrayFans(fans: [.init(rpm: 0, maximum: 7200)])
        XCTAssertEqual(stopped.fastest, 0)
        XCTAssertEqual(stopped.load, 0)
        XCTAssertEqual(stopped.state, "À l’arrêt · macOS")
        let missing = TrayFans(fans: [.init(rpm: nil, maximum: 7200)])
        XCTAssertNil(missing.fastest)
        XCTAssertNil(missing.load)
        XCTAssertEqual(missing.state, "Lecture partielle")
        XCTAssertEqual(TrayFans(fans: []).state, "Aucun ventilateur")
    }
    func testFanMaximumDoesNotCreateFalseLoadAndMultipleFansStayInspectable() {
        let fans = TrayFans(fans: [.init(rpm: 1800, maximum: nil), .init(rpm: 3600, maximum: 7200)])
        XCTAssertEqual(fans.fastest, 3600)
        XCTAssertEqual(fans.load, 0.5)
        XCTAssertTrue(fans.description.contains("Ventilateur 1 : 1800 tr/min"))
        XCTAssertTrue(fans.description.contains("Ventilateur 2 : 3600 tr/min"))
        XCTAssertNil(TrayFans.Fan(rpm: 1000, maximum: 0).load)
    }
    func testGPUHistoryResetsWhenAdapterChangesAndIsBounded() {
        var history = TrayGPUHistory()
        for time in 0..<100 {
            history.record(.init(sampledAt: Double(time), gpu: .init(id: 1, model: "Test", cores: 8, fraction: 0.2)))
        }
        XCTAssertLessThanOrEqual(history.points.count, 42)
        history.record(.init(sampledAt: 101, gpu: .init(id: 2, model: "Other", cores: 10, fraction: 0.5)))
        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.points.first?.value, 0.5)
        history.record(.init(sampledAt: 102))
        XCTAssertTrue(history.points.isEmpty)
    }
    func testShortcutSlotsKeepOrderAndAllowZeroThroughFour() {
        XCTAssertEqual(TrayShortcuts.slots(TrayShortcuts.defaults).compactMap { $0 }, [.cleaningOverview, .performanceOverview, .space, .maintenance])
        XCTAssertEqual(TrayShortcuts.slots("").compactMap { $0 }.count, 0)
        XCTAssertEqual(TrayShortcuts.slots("space,,maintenance,").map { $0?.rawValue }, ["space", nil, "maintenance", nil])
        XCTAssertEqual(TrayShortcuts.slots("space,space,invalid,devJunk,maintenance").map { $0?.rawValue }, ["space", nil, nil, nil])
    }
    func testSelectingExistingShortcutMovesItInsteadOfDuplicating() {
        let moved = TrayShortcuts.replacing(TrayShortcuts.defaults, at: 0, with: "space")
        XCTAssertEqual(TrayShortcuts.slots(moved).map { $0?.rawValue }, ["space", "performanceOverview", nil, "maintenance"])
        let removed = TrayShortcuts.replacing(moved, at: 3, with: "")
        XCTAssertEqual(TrayShortcuts.slots(removed).compactMap { $0 }.count, 2)
        XCTAssertEqual(TrayShortcuts.replacing(moved, at: 8, with: "space"), moved)
    }
}
