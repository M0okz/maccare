import XCTest
@testable import MacCare

final class TrayBatteryTelemetryTests: XCTestCase {
    func testAdapterRatingRejectsMissingUnknownAndBooleanValues() {
        XCTAssertEqual(TrayBatteryTelemetry.adapterPower(["Watts": 60]), 60)
        XCTAssertNil(TrayBatteryTelemetry.adapterPower([:]))
        XCTAssertNil(TrayBatteryTelemetry.adapterPower(["Watts": true]))
        XCTAssertNil(TrayBatteryTelemetry.adapterPower(["Watts": 0]))
        XCTAssertNil(TrayBatteryTelemetry.adapterPower(["Watts": -5]))
    }

    func testDevicePercentagesRequireRealPresentAndConsistentData() {
        XCTAssertEqual(TrayBatteryTelemetry.powerSourceAccessory(id: 1, properties: ["Name": "iPhone", "Current Capacity": 40, "Max Capacity": 80])?.percent, 50)
        XCTAssertNil(TrayBatteryTelemetry.powerSourceAccessory(id: 1, properties: ["Name": "iPhone", "Current Capacity": 40, "Max Capacity": 0]))
        XCTAssertNil(TrayBatteryTelemetry.powerSourceAccessory(id: 1, properties: ["Name": "iPhone", "Current Capacity": 40, "Max Capacity": 80, "Is Present": false]))
        XCTAssertNil(TrayBatteryTelemetry.accessory(id: 2, properties: ["Product": "AirPods", "BatteryPercent": true]))
        XCTAssertNil(TrayBatteryTelemetry.accessory(id: 2, properties: ["Product": "AirPods", "BatteryPercent": 150]))
        XCTAssertEqual(TrayBatteryTelemetry.accessory(id: 3, properties: ["Product": "Boîtier AirPods Pro", "BatteryPercent": 66])?.symbol, "airpods.chargingcase")
        XCTAssertEqual(TrayBatteryTelemetry.accessory(id: 4, properties: ["Product": "Showcase Keyboard", "BatteryPercent": 72])?.symbol, "keyboard")
    }

    func testProcessPowerUsesNanojoulesAndRequiresTwoCoherentReadings() {
        XCTAssertEqual(TrayProcessSampler.power(current: 5_000_000_000, previous: 1_000_000_000, seconds: 2), 2)
        XCTAssertNil(TrayProcessSampler.power(current: 1, previous: nil, seconds: 1))
        XCTAssertNil(TrayProcessSampler.power(current: 1, previous: 2, seconds: 1))
        XCTAssertNil(TrayProcessSampler.power(current: 2, previous: 1, seconds: 20))
        XCTAssertNil(TrayProcessSampler.power(current: 2, previous: 1, seconds: 0))
    }

    func testProcessCPUTimeUsesTheHostTickScale() {
        XCTAssertEqual(TrayProcessSampler.cpuLoad(current: 48_000_000, previous: 24_000_000, seconds: 1, nanosecondsPerTick: 125.0 / 3.0) ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(TrayProcessSampler.cpuLoad(current: 5_000_000_000, previous: 1_000_000_000, seconds: 1, nanosecondsPerTick: 1), 400)
        XCTAssertNil(TrayProcessSampler.cpuLoad(current: 1, previous: 2, seconds: 1, nanosecondsPerTick: 1))
        XCTAssertNil(TrayProcessSampler.cpuLoad(current: 1, previous: 0, seconds: 20, nanosecondsPerTick: 1))
    }

    func testVerySmallPowerIsNotRoundedToAFalseZero() {
        XCTAssertEqual(TrayBatteryTelemetry.Consumer(name: "Fixture", value: 0.003, measuredPower: true).formattedValue, "< 0,01 W")
        XCTAssertEqual(TrayBatteryTelemetry.Consumer(name: "Fixture", value: 0.03, measuredPower: true).formattedValue, "0,03 W")
        XCTAssertEqual(TrayBatteryTelemetry.Consumer(name: "Fixture", value: 0.003, measuredPower: false).formattedValue, "< 0,1 %")
    }

    func testCPUFallbackIsNotLabelledAsMeasuredPower() {
        let process = TrayProcess(id: .init(pid: 999_999, startedSeconds: 1, startedMicroseconds: 0), name: "Fixture",
                                  userID: getuid(), memory: 1, cpuPercent: 42, executable: "/tmp/fixture")
        let fallback = TrayBatteryTelemetry.leadingConsumer([process])
        XCTAssertEqual(fallback?.value, 42)
        XCTAssertEqual(fallback?.measuredPower, false)
        var measured = process
        measured.energyWatts = 1.2
        XCTAssertEqual(TrayBatteryTelemetry.leadingConsumer([measured])?.value, 1.2)
        XCTAssertEqual(TrayBatteryTelemetry.leadingConsumer([measured])?.measuredPower, true)
    }
}
