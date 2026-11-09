import XCTest
@testable import MacCare

final class MobileDeviceBatteryTests: XCTestCase {
    private let identifier = String(repeating: "a", count: 64)

    func testMissingMalformedOrUnknownBatteryValuesNeverBecomeZero() {
        let inputs = ["null", "true", "-1", "101", "12.5", "\"85\""]
        for input in inputs {
            let json = "{\"id\":\"\(identifier)\",\"name\":\"iPhone\",\"kind\":\"iphone\",\"percent\":\(input),\"viaPhone\":false}"
            XCTAssertTrue(MobileDeviceBatteryReader.parse(Data(json.utf8)).accessories.isEmpty, input)
        }
        XCTAssertTrue(MobileDeviceBatteryReader.parse(Data(repeating: 65, count: 32_769)).accessories.isEmpty)
    }

    func testPartialPhoneResultSurvivesFailedWatchReadWithoutClaimingCompletion() {
        let json = "{\"id\":\"\(identifier)\",\"name\":\"Téléphone\",\"kind\":\"iphone\",\"percent\":0,\"viaPhone\":false}\n{partial"
        let result = MobileDeviceBatteryReader.parse(Data(json.utf8))
        XCTAssertEqual(result.accessories.first?.percent, 0)
        XCTAssertEqual(result.accessories.first?.symbol, "iphone")
        XCTAssertFalse(result.complete)
    }

    func testWatchExplicitlyReportsLastValueKnownByPhoneAndDuplicatesAreRemoved() {
        let row = "{\"id\":\"\(identifier)\",\"name\":\"Ma montre\",\"kind\":\"watch\",\"percent\":80,\"viaPhone\":true}\n"
        let result = MobileDeviceBatteryReader.parse(Data((row + row + "{\"status\":\"complete\"}").utf8))
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.accessories.count, 1)
        XCTAssertEqual(result.accessories.first?.symbol, "applewatch")
        XCTAssertTrue(result.accessories.first?.levelDescription.contains("connu par l’iPhone") == true)
    }

    func testCompactCardsKeepPhoneAndWatchVisibleAlongsideHeadphones() {
        let devices: [TrayBatteryTelemetry.Accessory] = [
            .init(id: "1", name: "AirPods", symbol: "headphones", percent: 80),
            .init(id: "2", name: "Boîtier", symbol: "airpods.chargingcase", percent: 60),
            .init(id: "3", name: "Téléphone", symbol: "iphone", percent: 75),
            .init(id: "4", name: "Montre", symbol: "applewatch", percent: 50)
        ]
        let telemetry = TrayBatteryTelemetry(accessories: devices)
        XCTAssertEqual(telemetry.featuredAccessories.prefix(3).map(\.symbol), ["iphone", "applewatch", "headphones"])
        XCTAssertEqual(telemetry.accessories.count, 4, "The detail keeps the charging case available")
    }

    @MainActor
    func testPhoneRegistryProvenanceSurvivesDisplayHistoryAndDoesNotMergeDifferentPhones() {
        let controller = TrayBatteryController()
        let date = Date(timeIntervalSince1970: 100)
        let first = TrayBatteryTelemetry.Accessory(id: "mobile:1", name: "Montre", symbol: "applewatch", percent: 50,
                                                  receivedAt: date, viaPhone: true)
        controller.record(.init(accessories: [first]), at: 100)
        XCTAssertEqual(controller.telemetry.accessories.first?.receivedAt, date)
        XCTAssertEqual(controller.telemetry.accessories.first?.viaPhone, true)
        let second = TrayBatteryTelemetry.Accessory(id: "mobile:2", name: "Montre", symbol: "applewatch", percent: 90,
                                                   receivedAt: date, viaPhone: true)
        controller.record(.init(accessories: [second]), at: 105)
        XCTAssertEqual(controller.telemetry.accessories.count, 2)
    }

    func testAbsentProbeReturnsUnavailableWithoutInventingAnAccessory() async {
        let result = await MobileDeviceBatteryReader.read(executable: URL(fileURLWithPath: "/nonexistent/MacCareDeviceBatteryProbe"))
        XCTAssertFalse(result.complete)
        XCTAssertTrue(result.accessories.isEmpty)
    }

    func testProbeDeadlineStopsBlockedReaderAndKeepsAlreadyReceivedPhone() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("blocked-reader")
        let row = "{\"id\":\"\(identifier)\",\"name\":\"iPhone\",\"kind\":\"iphone\",\"percent\":77,\"viaPhone\":false}"
        try Data("#!/bin/sh\nprintf '%s\\n' '\(row)'\nexec /bin/sleep 30\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let start = ProcessInfo.processInfo.systemUptime
        let result = await MobileDeviceBatteryReader.read(executable: executable)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 8)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.accessories.first?.percent, 77)
    }

    func testSharedCacheLimitsSuccessfulReadsAndExpiresOldValues() async {
        let counter = Counter()
        let device = TrayBatteryTelemetry.Accessory(id: "mobile:\(identifier)", name: "iPhone", symbol: "iphone", percent: 80)
        let store = MobileDeviceBatteryStore {
            let count = await counter.increment()
            return .init(accessories: count == 1 ? [device] : [], complete: true)
        }
        let first = await store.accessories(at: 100, lowPower: false)
        let cached = await store.accessories(at: 159, lowPower: false)
        XCTAssertNotNil(first.first?.receivedAt)
        XCTAssertEqual(cached.first?.percent, 80)
        var count = await counter.count
        XCTAssertEqual(count, 1)
        let missing = await store.accessories(at: 160, lowPower: false)
        XCTAssertTrue(missing.isEmpty)
        _ = await store.accessories(at: 459, lowPower: false)
        count = await counter.count
        XCTAssertEqual(count, 2, "No phone: wait five minutes before another connection attempt")
        _ = await store.accessories(at: 460, lowPower: false)
        count = await counter.count
        XCTAssertEqual(count, 3)
    }

    func testLowPowerCadenceAndFailureExpiry() async {
        let counter = Counter()
        let device = TrayBatteryTelemetry.Accessory(id: "mobile:\(identifier)", name: "iPhone", symbol: "iphone", percent: 75)
        let store = MobileDeviceBatteryStore {
            _ = await counter.increment()
            return .init(accessories: [device], complete: false)
        }
        _ = await store.accessories(at: 100, lowPower: true)
        let expired = await store.accessories(at: 280, lowPower: true)
        XCTAssertTrue(expired.isEmpty)
        var count = await counter.count
        XCTAssertEqual(count, 1)
        let success = MobileDeviceBatteryStore {
            _ = await counter.increment()
            return .init(accessories: [device], complete: true)
        }
        _ = await success.accessories(at: 500, lowPower: true)
        _ = await success.accessories(at: 619, lowPower: true)
        count = await counter.count
        XCTAssertEqual(count, 2)
        _ = await success.accessories(at: 620, lowPower: true)
        count = await counter.count
        XCTAssertEqual(count, 3)
    }

    func testSimultaneousViewsStartOnlyOneAcquisition() async {
        let gate = Gate()
        let store = MobileDeviceBatteryStore { await gate.read() }
        let first = Task { await store.accessories(at: 100, lowPower: false) }
        await gate.waitUntilStarted()
        let second = await store.accessories(at: 100, lowPower: false)
        XCTAssertTrue(second.isEmpty)
        await gate.finish()
        _ = await first.value
        let count = await gate.count
        XCTAssertEqual(count, 1)
    }
}

private actor Counter {
    var count = 0
    func increment() -> Int { count += 1; return count }
}

private actor Gate {
    var count = 0
    var started: CheckedContinuation<Void, Never>?
    var completion: CheckedContinuation<MobileDeviceBatteryReader.Result, Never>?
    func read() async -> MobileDeviceBatteryReader.Result {
        count += 1
        started?.resume(); started = nil
        return await withCheckedContinuation { completion = $0 }
    }
    func waitUntilStarted() async {
        if count > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { completion?.resume(returning: .init(complete: true)); completion = nil }
}
