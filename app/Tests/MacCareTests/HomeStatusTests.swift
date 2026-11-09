import XCTest
import IOKit.ps
import MacCareBattery
@testable import MacCare

final class HomeStatusTests: XCTestCase {
    private func powerSource(time: Any = 380, onAC: Bool = false, charging: Bool = false) -> [String: Any] {
        [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 76, kIOPSMaxCapacityKey: 100,
         kIOPSIsPresentKey: true, kIOPSPowerSourceStateKey: onAC ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
         kIOPSIsChargingKey: charging, kIOPSTimeToEmptyKey: time, kIOPSBatteryHealthKey: kIOPSGoodValue]
    }
    func testBatterySummaryUsesIOPSStateAndMinutesWithoutInventingAnEstimate() {
        let original = BatterySnapshot(percent: 12, cycles: 248, healthPercent: 94)
        let measured = original.applyingPowerSources([powerSource()])
        XCTAssertEqual(HomeBatteryPresentation.charge(measured), "76 %")
        XCTAssertEqual(HomeBatteryPresentation.remaining(measured), "Environ 6 h 20 min restantes")
        XCTAssertEqual(HomeBatteryPresentation.condition(measured), "Normal")
        let invalidTimes: [Any] = [-1, 0, true, Double.nan, "380"]
        for time in invalidTimes {
            XCTAssertNil(HomeBatteryPresentation.remaining(original.applyingPowerSources([powerSource(time: time)])))
        }
        XCTAssertNil(HomeBatteryPresentation.remaining(original.applyingPowerSources([powerSource(onAC: true)])))
        XCTAssertNil(HomeBatteryPresentation.remaining(original.applyingPowerSources([powerSource(charging: true)])))
    }
    func testMissingBatteryAndMissingConditionAreNotReportedAsHealthyOrEmpty() {
        XCTAssertEqual(HomeBatteryPresentation.charge(nil), "—")
        XCTAssertEqual(HomeBatteryPresentation.charge(.init(present: false, percent: 90)), "—")
        XCTAssertEqual(HomeBatteryPresentation.charge(.init(percent: 130)), "—")
        XCTAssertEqual(HomeBatteryPresentation.condition(.init(percent: 90)), "Aucune alerte", "Never « Normal » without a value from macOS")
        XCTAssertEqual(HomeBatteryPresentation.condition(.init(percent: 90, powerStateKnown: false)), "Indisponible")
        XCTAssertEqual(HomeBatteryPresentation.condition(.init(batteryFault: true)), "À vérifier")
        var withoutHealth = powerSource()
        withoutHealth[kIOPSBatteryHealthKey] = nil
        XCTAssertEqual(HomeBatteryPresentation.condition(BatterySnapshot().applyingPowerSources([withoutHealth])), "Aucune alerte")
        var source = powerSource()
        source[kIOPSBatteryHealthConditionKey] = kIOPSCheckBatteryValue
        XCTAssertEqual(HomeBatteryPresentation.condition(BatterySnapshot().applyingPowerSources([source])), "À vérifier")
    }
    func testLegacyBatteryRepliesDecodeWithMissingInformationalFields() throws {
        let original = BatterySnapshot(percent: 76)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "healthState"); json.removeValue(forKey: "minutesRemaining")
        let decoded = try JSONDecoder().decode(BatterySnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.percent, 76)
        XCTAssertNil(decoded.healthState); XCTAssertNil(decoded.minutesRemaining)
    }
    @MainActor func testHomeAndMenuShareMonitoringWithoutStoppingOtherWindows() {
        let store = TrayMetricsStore()
        let first = TrayMetricsStore.Consumer.dashboard(UUID())
        let second = TrayMetricsStore.Consumer.dashboard(UUID())
        defer { store.stop() }
        store.setMonitoring(for: .menuBar, enabled: true)
        store.setMonitoring(for: first, enabled: true)
        store.setMonitoring(for: second, enabled: true)
        store.setMonitoring(for: .menuBar, enabled: false)
        XCTAssertTrue(store.isMonitoring)
        store.setMonitoring(for: first, enabled: false)
        XCTAssertTrue(store.isMonitoring)
        store.setMonitoring(for: second, enabled: false)
        XCTAssertTrue(store.isMonitoring)
        XCTAssertFalse(store.isForeground)
    }
    @MainActor func testSleepSuspendsSharedMonitoringAndWakeReturnsToBackground() {
        let store = TrayMetricsStore(), home = TrayMetricsStore.Consumer.dashboard(UUID())
        defer { store.stop() }
        store.setMonitoring(for: home, enabled: true)
        store.suspend()
        XCTAssertFalse(store.isMonitoring)
        store.setMonitoring(for: .menuBar, enabled: true)
        XCTAssertFalse(store.isMonitoring)
        store.resume()
        XCTAssertTrue(store.isMonitoring)
        store.suspend()
        store.setMonitoring(for: home, enabled: false)
        store.setMonitoring(for: .menuBar, enabled: false)
        store.resume()
        XCTAssertTrue(store.isMonitoring)
        XCTAssertFalse(store.isForeground)
    }

    @MainActor func testActivityWindowsKeepFastMonitoringUntilTheLastConsumerCloses() {
        let store = TrayMetricsStore()
        let home = TrayMetricsStore.Consumer.dashboard(UUID())
        let windows = (0..<3).map { _ in TrayMetricsStore.Consumer.activityDetail(UUID()) }
        defer { store.stop() }
        store.setMonitoring(for: .menuBar, enabled: true)
        store.setMonitoring(for: home, enabled: true)
        for window in windows { store.setMonitoring(for: window, enabled: true) }
        store.setMonitoring(for: .menuBar, enabled: false)
        store.setMonitoring(for: home, enabled: false)
        XCTAssertTrue(store.isMonitoring)
        for window in windows.dropLast() {
            store.setMonitoring(for: window, enabled: false)
            XCTAssertTrue(store.isMonitoring)
        }
        store.suspend()
        XCTAssertFalse(store.isMonitoring)
        store.resume()
        XCTAssertTrue(store.isMonitoring)
        store.setMonitoring(for: windows[2], enabled: false)
        XCTAssertTrue(store.isMonitoring)
        XCTAssertFalse(store.isForeground)
    }
}
