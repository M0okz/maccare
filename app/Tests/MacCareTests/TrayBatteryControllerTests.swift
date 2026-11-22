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

    @MainActor
    func testHomeRingsKeepTheirSlotsAndReconnectEvenAtTheSameOrLowerLevel() throws {
        let suite = testPreferencesSuite("HomeAccessoryRings")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = TrayBatteryController(accessoryHistory: .init(defaults: defaults))
        let mouse = device("hid:1", "Souris", 30)
        let keyboard = device("hid:2", "Clavier", 65)
        controller.record(.init(accessories: [mouse, keyboard]), at: 10)
        let ids = controller.homeAccessories.map(\.id)
        controller.record(.init(accessories: [keyboard]), at: 29)
        XCTAssertEqual(controller.homeAccessories.map(\.isLastKnown), [false, false])
        controller.record(.init(accessories: [keyboard]), at: 30)
        XCTAssertEqual(controller.homeAccessories.map(\.id), ids)
        XCTAssertEqual(controller.homeAccessories.map(\.isLastKnown), [true, false])
        XCTAssertTrue(controller.homeAccessories[0].levelDescription.contains("Hors ligne"))
        XCTAssertEqual(controller.telemetry.accessories.map(\.name), ["Clavier"])
        controller.record(.init(accessories: [device("power:8", "Souris", 30), keyboard]), at: 35)
        XCTAssertEqual(controller.homeAccessories.map(\.id), ids)
        XCTAssertFalse(controller.homeAccessories[0].isLastKnown)
        controller.record(.init(), at: 60)
        controller.record(.init(accessories: [device("power:8", "Souris", 25)]), at: 65)
        XCTAssertEqual(controller.homeAccessories.map(\.percent), [25, 65])
        XCTAssertEqual(controller.homeAccessories.map(\.isLastKnown), [false, true])
    }

    @MainActor
    func testRestoredHomeRingsStartGreyAndPreferNewLiveReadings() throws {
        let suite = testPreferencesSuite("HomeAccessoryRestore")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = TrayBatteryController(accessoryHistory: .init(defaults: defaults))
        first.record(.init(), at: 1)
        XCTAssertTrue(first.homeAccessories.isEmpty)
        let entries = (1...4).map { device("mobile:\($0)", "Appareil \($0)", $0 * 10) }
        first.record(.init(accessories: entries), at: 2)
        let restored = TrayBatteryController(accessoryHistory: .init(defaults: defaults))
        XCTAssertEqual(restored.homeAccessories.map(\.percent), [10, 20, 30])
        XCTAssertTrue(restored.homeAccessories.allSatisfy(\.isLastKnown))
        let next = device("mobile:5", "Appareil 1", 40)
        restored.record(.init(accessories: [next]), at: 3)
        XCTAssertEqual(restored.homeAccessories.count, 3)
        XCTAssertEqual(restored.homeAccessories.filter { !$0.isLastKnown }.map(\.percent), [40])
        restored.record(.init(accessories: Array(entries.dropFirst())), at: 30)
        XCTAssertEqual(restored.homeAccessories.map(\.percent), [20, 30, 40])
        XCTAssertTrue(restored.homeAccessories.allSatisfy { !$0.isLastKnown })
    }

    private func device(_ id: String, _ name: String, _ percent: Int) -> TrayBatteryTelemetry.Accessory {
        .init(id: id, name: name, symbol: "headphones", percent: percent)
    }
}
