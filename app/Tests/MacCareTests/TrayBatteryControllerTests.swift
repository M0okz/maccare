import XCTest
@testable import MacCare

final class TrayBatteryControllerTests: XCTestCase {
    @MainActor
    func testOneMissingAccessoryReadDoesNotCollapseTheConnectedDevicesSection() {
        let controller = TrayBatteryController()
        let devices: [TrayBatteryTelemetry.Accessory] = [
            .init(id: "power:1", name: "AirPods", symbol: "headphones", percent: 80),
            .init(id: "power:2", name: "Boîtier AirPods", symbol: "airpods.chargingcase", percent: 60)
        ]
        controller.record(.init(accessories: devices), at: 100)
        let displayed = controller.telemetry.accessories.map(\.id)
        controller.record(.init(accessories: []), at: 105)
        XCTAssertEqual(controller.telemetry.accessories.map(\.id), displayed,
                       "Un relevé vide transitoire ne doit pas faire disparaître les anneaux et déplacer les cartes.")
    }

    @MainActor
    func testPartialReadsUpdateLevelsWithoutReorderingOrRemovingTheOtherDevice() {
        let controller = TrayBatteryController()
        controller.record(.init(accessories: [device("1", "Écouteurs", 80), device("2", "Boîtier", 60)]), at: 100)
        let ids = controller.telemetry.accessories.map(\.id)
        controller.record(.init(accessories: [device("2", "Boîtier", 59)]), at: 105)
        XCTAssertEqual(controller.telemetry.accessories.map(\.id), ids)
        XCTAssertEqual(controller.telemetry.accessories.map(\.percent), [80, 59])
        controller.record(.init(accessories: [device("changed", "Boîtier", 58), device("1", "Écouteurs", 79)]), at: 110)
        XCTAssertEqual(controller.telemetry.accessories.map(\.id), ids)
        XCTAssertEqual(controller.telemetry.accessories.map(\.percent), [79, 58])
    }

    @MainActor
    func testMissingDevicesExpireIndividuallyWithoutFreezingFreshTelemetry() {
        let controller = TrayBatteryController()
        controller.record(.init(accessories: [device("1", "Écouteurs", 80), device("2", "Boîtier", 60)]), at: 100)
        controller.record(.init(adapterWatts: 65, accessories: [device("1", "Écouteurs", 79)]), at: 115)
        XCTAssertEqual(controller.telemetry.accessories.count, 2)
        XCTAssertEqual(controller.telemetry.adapterWatts, 65)
        controller.record(.init(adapterWatts: 30, accessories: []), at: 120)
        XCTAssertEqual(controller.telemetry.accessories.map(\.name), ["Écouteurs"])
        XCTAssertEqual(controller.telemetry.adapterWatts, 30)
        controller.record(.init(), at: 135)
        XCTAssertTrue(controller.telemetry.accessories.isEmpty)
    }

    @MainActor
    func testAnEmptyFirstReadingDoesNotInventAccessoriesAndAClockResetDropsOldData() {
        let controller = TrayBatteryController()
        controller.record(.init(), at: 100)
        XCTAssertTrue(controller.hasSampled)
        XCTAssertTrue(controller.telemetry.accessories.isEmpty)
        controller.record(.init(accessories: [device("1", "Écouteurs", 80)]), at: 105)
        controller.record(.init(), at: 10)
        XCTAssertTrue(controller.telemetry.accessories.isEmpty)
    }

    @MainActor
    func testTwoDevicesWithTheSameNameAreNotMerged() {
        let controller = TrayBatteryController()
        controller.record(.init(accessories: [device("1", "Souris", 10), device("2", "Souris", 90)]), at: 100)
        let ids = controller.telemetry.accessories.map(\.id)
        XCTAssertEqual(Set(ids).count, 2)
        controller.record(.init(accessories: [device("2", "Souris", 89), device("1", "Souris", 9)]), at: 105)
        XCTAssertEqual(controller.telemetry.accessories.map(\.id), ids)
        XCTAssertEqual(controller.telemetry.accessories.map(\.percent), [9, 89])
    }

    private func device(_ id: String, _ name: String, _ percent: Int) -> TrayBatteryTelemetry.Accessory {
        .init(id: id, name: name, symbol: "headphones", percent: percent)
    }
}
