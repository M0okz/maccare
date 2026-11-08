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

    func testMacCareAndItsHelpersCannotLeadThePowerOrCPUClassification() {
        let app = process(name: "Other app", path: "/Applications/Other.app/Contents/MacOS/Other", watts: 0.4)
        let excluded = [
            process(name: "Renamed", path: "/tmp/custom", watts: 9, pid: getpid()),
            process(name: "MacCare", path: "/Applications/MacCare.app/Contents/MacOS/MacCare", watts: 8),
            process(name: "MacCare Dev", path: "/Applications/MacCare Dev.app/Contents/MacOS/MacCare", watts: 7),
            process(name: "MacCareHelper", path: "/Library/PrivilegedHelperTools/org.maccare.helper", watts: 6),
            process(name: "Updater", path: "/Applications/MacCare.app/Contents/Frameworks/Updater", watts: 5),
            process(name: "MacCareHelper", path: "", watts: 4)
        ]
        XCTAssertEqual(TrayBatteryTelemetry.leadingConsumer(excluded + [app])?.name, "Other app")
        XCTAssertNil(TrayBatteryTelemetry.leadingConsumer(excluded))
        var cpuApp = app
        cpuApp.energyWatts = nil
        let cpuExcluded = excluded.map { process in var process = process; process.energyWatts = nil; return process }
        XCTAssertEqual(TrayBatteryTelemetry.leadingConsumer(cpuExcluded + [cpuApp])?.name, "Other app")
        XCTAssertNil(TrayBatteryTelemetry.leadingConsumer(cpuExcluded))
        XCTAssertEqual(TrayBatteryTelemetry.leadingConsumer([process(name: "MacCare Notes", path: "/Applications/MacCare Notes.app/Contents/MacOS/Notes", watts: 1)])?.name, "MacCare Notes")
    }

    func testLongerBatteryMeasurementsRemainValidWithoutChangingTheFastProcessLists() {
        XCTAssertEqual(TrayProcessSampler.power(current: 31_000_000_000, previous: 1_000_000_000, seconds: 15, maximumInterval: 30), 2)
        XCTAssertEqual(TrayProcessSampler.cpuLoad(current: 16_000_000_000, previous: 1_000_000_000, seconds: 15, nanosecondsPerTick: 1, maximumInterval: 30), 100)
        XCTAssertNil(TrayProcessSampler.power(current: 31_000_000_000, previous: 1_000_000_000, seconds: 15))
        XCTAssertNil(TrayProcessSampler.power(current: 31_000_000_000, previous: 1_000_000_000, seconds: 31, maximumInterval: 30))
    }

    func testConsumerSamplingPrimesThenWaitsFifteenSecondsAndReprimesAfterASuspension() {
        var cadence = TrayBatteryProcessCadence()
        XCTAssertTrue(cadence.shouldSample(at: 100))
        XCTAssertFalse(cadence.shouldSample(at: 100.5))
        XCTAssertTrue(cadence.shouldSample(at: 101))
        for time in [101.5, 106, 111, 115.9] { XCTAssertFalse(cadence.shouldSample(at: time)) }
        XCTAssertTrue(cadence.shouldSample(at: 116))
        XCTAssertFalse(cadence.shouldSample(at: 121))
        XCTAssertTrue(cadence.shouldSample(at: 131))
        XCTAssertTrue(cadence.shouldSample(at: 200))
        XCTAssertTrue(cadence.shouldSample(at: 201))
        XCTAssertFalse(cadence.shouldSample(at: 206))
        XCTAssertTrue(cadence.shouldSample(at: 216))
        XCTAssertTrue(cadence.shouldSample(at: 10))
        XCTAssertTrue(cadence.shouldSample(at: 11))
        XCTAssertFalse(cadence.shouldSample(at: 16))
    }

    private func process(name: String, path: String, watts: Double, pid: pid_t = 999_999) -> TrayProcess {
        .init(id: .init(pid: pid, startedSeconds: 1, startedMicroseconds: 0), name: name,
              userID: getuid(), memory: 1, cpuPercent: 80, executable: path, energyWatts: watts)
    }
}
