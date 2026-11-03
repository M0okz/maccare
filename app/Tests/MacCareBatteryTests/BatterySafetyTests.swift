import XCTest
import MacCareBattery
import Darwin
import IOKit.ps

final class BatterySafetyTests: XCTestCase {
    private let session = UUID()
    private final class Hardware: ChargeHardware {
        var firmwareManaged = false
        var value: UInt8 = 0
        var writes: [UInt8] = []
        var fails = false
        var failNextChange = false
        var records: [BatteryRecoveryRecord] = []
        var ended = false
        func readSwitch() throws -> UInt8 { value }
        func writeSwitch(_ value: UInt8) throws {
            if fails || failNextChange { failNextChange = false; throw Failure() }
            writes.append(value); self.value = value
        }
        func setFirmwareLimit(_ limit: Int?) throws { try writeSwitch(limit == nil ? 0 : 2) }
        func captureRecovery() throws -> BatteryRecoveryRecord {
            guard value == 0 else { throw Failure() }
            return .init(backend: firmwareManaged ? .firmware : .legacyPair,
                         firmwareUpper: firmwareManaged ? 95 : nil, firmwareLower: firmwareManaged ? 90 : nil)
        }
        func restore(_ record: BatteryRecoveryRecord) throws {
            if value != 0 { try writeSwitch(0) }
            records.append(record)
        }
        func endSession() { ended = true }
    }
    private struct Failure: Error {}
    private func sample(_ percent: Int = 80) -> BatterySnapshot { .init(percent: percent, onAC: true, temperature: 30) }
    private func controller(_ hardware: Hardware) -> BatteryProtectionController {
        .init(hardware: hardware, markRecovery: { _ in }, clearRecovery: {})
    }
    func testUnknownServiceSupervisionNeverDefaultsToReady() {
        XCTAssertFalse(BatteryProtectionStatus(snapshot: sample()).recoveryReady)
    }
    func testStatusIsReadOnlyEvenWhenPolicyOrLeaseWouldChange() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(50), now: 0)
        let before = hardware.writes
        _ = controller.execute(.status, configuration: nil, uid: 502, snapshot: sample(90), now: 10)
        _ = controller.execute(.status, configuration: nil, uid: 501, snapshot: sample(90), now: 100)
        XCTAssertEqual(hardware.writes, before)
        XCTAssertTrue(controller.requiresWatchdog)
        XCTAssertFalse(controller.tick(snapshot: sample(90), now: 100).active)
    }
    func testFailedDisableNeverResumesPolicyOrRenewsLease() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(), now: 0)
        hardware.fails = true
        let failed = controller.execute(.disable, configuration: nil, uid: 501, sessionID: session, snapshot: sample(), now: 1)
        XCTAssertFalse(failed.active); XCTAssertTrue(failed.restoring)
        let heartbeat = controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: session, snapshot: sample(), now: 2)
        XCTAssertFalse(heartbeat.active); XCTAssertTrue(heartbeat.restoring)
        hardware.fails = false
        let restored = controller.tick(snapshot: sample(), now: 3)
        XCTAssertFalse(restored.active); XCTAssertFalse(restored.restoring)
        XCTAssertEqual(hardware.value, 0)
        XCTAssertEqual(hardware.writes.last, 0)
    }
    func testReconfigurationFailureStopsInsteadOfContinuingOldProtection() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(50), now: 0)
        hardware.failNextChange = true
        let failed = controller.execute(.enable, configuration: .init(limit: 50), uid: 501, sessionID: session, snapshot: sample(60), now: 1)
        XCTAssertFalse(failed.active); XCTAssertNotNil(failed.error)
        XCTAssertFalse(controller.requiresWatchdog)
        XCTAssertEqual(hardware.value, 0)
    }
    func testWakeRequiresFreshHeartbeatAndTimesOutWithoutOne() throws {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(), now: 0)
        try controller.prepareForSleep()
        controller.didWake(now: 1_000)
        let writes = hardware.writes
        XCTAssertFalse(controller.tick(snapshot: sample(), now: 1_001).suspended)
        _ = controller.execute(.status, configuration: nil, uid: 501, sessionID: session, snapshot: sample(), now: 1_002)
        XCTAssertEqual(hardware.writes, writes)
        XCTAssertFalse(controller.tick(snapshot: sample(), now: 1_015).active)
        XCTAssertEqual(hardware.value, 0)
    }
    func testDifferentInstanceCannotRenewButSameUserCanExplicitlyStop() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(), now: 0)
        let other = UUID()
        let denied = controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: other, snapshot: sample(), now: 10)
        XCTAssertNotNil(denied.error); XCTAssertFalse(denied.ownedByCaller)
        XCTAssertTrue(controller.execute(.status, configuration: nil, uid: 501, sessionID: session, snapshot: sample(), now: 11).ownedByCaller)
        let stopped = controller.execute(.disable, configuration: nil, uid: 501, sessionID: other, snapshot: sample(), now: 12)
        XCTAssertFalse(stopped.active); XCTAssertFalse(stopped.restoring)
        XCTAssertEqual(hardware.value, 0)
    }
    func testMissingSessionAndUnknownPowerStateCannotMutate() {
        let hardware = Hardware(), controller = controller(hardware)
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 501, snapshot: sample(), now: 0).error)
        var unknown = sample(); unknown.powerStateKnown = false
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: unknown, now: 1).error)
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testRestorationKeepsOriginalFirmwareThresholdsAndBackend() {
        let hardware = Hardware(); hardware.firmwareManaged = true
        let controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(thermalProtection: false), uid: 501, sessionID: session, snapshot: sample(), now: 0)
        // Discovery would now report a different backend: restoration must still use the record.
        hardware.firmwareManaged = false
        _ = controller.execute(.disable, configuration: nil, uid: 501, sessionID: session, snapshot: sample(), now: 1)
        XCTAssertEqual(hardware.records.last, .init(backend: .firmware, firmwareUpper: 95, firmwareLower: 90))
        XCTAssertTrue(hardware.ended)
    }
    func testTickFailureRemainsVisibleAfterSuccessfulRestoration() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: session, snapshot: sample(50), now: 0)
        hardware.failNextChange = true
        let result = controller.tick(snapshot: sample(90), now: 1)
        XCTAssertFalse(result.active); XCTAssertNotNil(result.error)
    }
    func testNonFiniteTelemetryNeverTrapsOrPermitsThermalCharging() {
        for number in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude] {
            let result = BatterySnapshot.decode([
                "CurrentCapacity": number, "MaxCapacity": 100, "CycleCount": number,
                "FullChargeCapacity": number, "DesignCapacity": Double.leastNonzeroMagnitude,
                "Temperature": number
            ], appleSilicon: true)
            XCTAssertNil(result.percent)
            XCTAssertNil(result.cycles)
            XCTAssertFalse(result.reliableForControl)
        }
        var policy = BatteryProtectionPolicy()
        var bad = sample(); bad.temperature = .nan
        XCTAssertTrue(policy.evaluate(bad, configuration: .init(), topUp: true).suspend)
        bad.temperature = .infinity
        XCTAssertTrue(policy.evaluate(bad, configuration: .init(), topUp: true).suspend)
    }
    func testTelemetryDoesNotMixUnitsOrTreatBooleanAsCapacity() {
        XCTAssertNil(BatterySnapshot.decode(["CurrentCapacity": 80, "BatteryData": ["MaxCapacity": 5000]], appleSilicon: true).percent)
        XCTAssertNil(BatterySnapshot.decode(["CurrentCapacity": true, "MaxCapacity": 100], appleSilicon: true).percent)
    }
    func testInternalBatterySourceWinsOverUPSAndUsesMacOSPercentage() {
        let raw = BatterySnapshot(percent: 95, onAC: false, temperature: 30)
        let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSCurrentCapacityKey: 99, kIOPSMaxCapacityKey: 100]
        let internalBattery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: false, kIOPSIsPresentKey: true]
        let result = raw.applyingPowerSources([ups, internalBattery])
        XCTAssertEqual(result.percent, 80)
        XCTAssertTrue(result.reliableForControl); XCTAssertTrue(result.onAC)
        XCTAssertFalse(raw.applyingPowerSources([ups]).reliableForControl)
        var unknown = internalBattery; unknown[kIOPSPowerSourceStateKey] = "Unrecognised"
        XCTAssertFalse(raw.applyingPowerSources([unknown]).reliableForControl)
    }
    func testFaultyBatteryAndZeroTemperatureFailClosed() {
        let result = BatterySnapshot.decode(["BatteryInstalled": true, "CurrentCapacity": 80, "MaxCapacity": 100,
            "ExternalConnected": true, "IsCharging": false, "PermanentFailureStatus": 1, "Temperature": 0], appleSilicon: true)
        XCTAssertTrue(result.batteryFault); XCTAssertFalse(result.reliableForControl)
        XCTAssertNil(result.temperature)
        var policy = BatteryProtectionPolicy()
        var snapshot = sample(); snapshot.temperature = nil
        XCTAssertTrue(policy.evaluate(snapshot, configuration: .init(), topUp: true).suspend)
        snapshot.temperature = 34
        XCTAssertTrue(policy.evaluate(snapshot, configuration: .init(), topUp: true).suspend)
        snapshot.temperature = 33
        XCTAssertFalse(policy.evaluate(snapshot, configuration: .init(), topUp: true).suspend)
    }
    func testRecoveryForAnotherMachineIsRejected() {
        let hardware = AppleSiliconChargeHardware()
        XCTAssertThrowsError(try hardware.restore(.init(backend: .legacyPair, machineID: "another-machine")))
    }
    func testUnknownRecordVersionOrBackendCannotRestore() throws {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(BatteryRecoveryRecord.self, from: Data(#"{"version":1,"machineID":"fixture","backend":99}"#.utf8)))
        let future = try decoder.decode(BatteryRecoveryRecord.self, from: Data(#"{"version":2,"machineID":"fixture","backend":1}"#.utf8))
        XCTAssertFalse(future.isValid)
    }
    func testRecoveryStoreRoundtripAndNoOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maccare-battery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryRecoveryStore(directory: directory, owner: geteuid())
        XCTAssertNil(try store.load())
        let record = BatteryRecoveryRecord(backend: .firmware, firmwareUpper: 100, firmwareLower: 97)
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
        XCTAssertThrowsError(try store.save(record))
        try store.clear(); XCTAssertNil(try store.load())
    }
    func testRecoveryStoreRefusesLinksCorruptionAndLoosePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("maccare-battery-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryRecoveryStore(directory: directory, owner: geteuid())
        let file = directory.appendingPathComponent("battery-charge-recovery")
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: directory.appendingPathComponent("missing").path)
        XCTAssertThrowsError(try store.load())
        try FileManager.default.removeItem(at: file)
        try Data("MacCare charge gates restore 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertThrowsError(try store.load())
        try FileManager.default.removeItem(at: file)
        try store.save(.init(backend: .legacyPair))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try store.load())
    }
}
