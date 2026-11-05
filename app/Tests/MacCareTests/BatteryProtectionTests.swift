import XCTest
import MacCareBattery
@testable import MacCare

final class BatteryProtectionTests: XCTestCase {
    private static let session = UUID()
    private final class Hardware: ChargeHardware {
        var firmwareManaged = false
        var firmwareLimit: Int?
        var value: UInt8 = 0
        var writes: [UInt8] = []
        var failWrites = false
        func readSwitch() throws -> UInt8 { value }
        func setFirmwareLimit(_ limit: Int?) throws {
            if failWrites { throw Failure() }
            firmwareLimit = limit
            value = limit == nil ? 0 : 2
        }
        func writeSwitch(_ value: UInt8) throws {
            if failWrites { throw Failure() }
            writes.append(value); self.value = value
        }
    }
    private struct Failure: Error {}
    private func snapshot(_ percent: Int = 80, temperature: Double? = 30, onAC: Bool = true) -> BatterySnapshot {
        .init(percent: percent, onAC: onAC, temperature: temperature)
    }
    private func controller(_ hardware: Hardware) -> BatteryProtectionController {
        .init(hardware: hardware, markRecovery: { _ in }, clearRecovery: {})
    }
    func testChargeLimitAndHysteresis() {
        var policy = BatteryProtectionPolicy()
        let config = BatteryConfiguration()
        XCTAssertFalse(policy.evaluate(snapshot(79), configuration: config, topUp: false).suspend)
        XCTAssertTrue(policy.evaluate(snapshot(80), configuration: config, topUp: false).suspend)
        XCTAssertTrue(policy.evaluate(snapshot(78), configuration: config, topUp: false).suspend)
        XCTAssertFalse(policy.evaluate(snapshot(77), configuration: config, topUp: false).suspend)
    }
    func testThermalHysteresisAlsoAppliesToTopUp() {
        var policy = BatteryProtectionPolicy()
        let config = BatteryConfiguration()
        XCTAssertTrue(policy.evaluate(snapshot(50, temperature: 35), configuration: config, topUp: true).suspend)
        XCTAssertTrue(policy.evaluate(snapshot(50, temperature: 34), configuration: config, topUp: true).suspend)
        XCTAssertFalse(policy.evaluate(snapshot(50, temperature: 33), configuration: config, topUp: true).suspend)
        XCTAssertTrue(policy.evaluate(snapshot(50, temperature: nil), configuration: config, topUp: true).suspend)
        XCTAssertFalse(policy.evaluate(snapshot(50, temperature: nil), configuration: .init(thermalProtection: false), topUp: false).suspend)
    }
    func testNoControlWithoutValidAppleSiliconBattery() {
        let hardware = Hardware(), controller = controller(hardware)
        for sample in [BatterySnapshot(present: false), BatterySnapshot(appleSilicon: false), BatterySnapshot(percent: nil)] {
            let result = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: sample, now: 0)
            XCTAssertFalse(result.active); XCTAssertNotNil(result.error)
        }
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testFirmwareLimitBackendAppliesBandAndRejectsCustomThermalControl() throws {
        let hardware = Hardware(); hardware.firmwareManaged = true
        let controller = controller(hardware)
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0).error)
        XCTAssertTrue(hardware.writes.isEmpty)
        let enabled = controller.execute(.enable, configuration: .init(thermalProtection: false), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 1)
        XCTAssertTrue(enabled.active); XCTAssertTrue(enabled.firmwareManaged)
        XCTAssertEqual(hardware.firmwareLimit, 80)
        _ = controller.execute(.topUp, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 2)
        XCTAssertNil(hardware.firmwareLimit)
        _ = controller.execute(.cancelTopUp, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 3)
        XCTAssertEqual(hardware.firmwareLimit, 80)
        XCTAssertFalse(controller.tick(snapshot: snapshot(), now: 94).active)
        XCTAssertEqual(hardware.value, 0)
    }
    func testReadAccessWithoutWritePermissionCannotActivateProtection() {
        let hardware = Hardware(); hardware.failWrites = true
        let controller = controller(hardware)
        let result = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        XCTAssertFalse(result.active); XCTAssertNotNil(result.error)
        XCTAssertFalse(controller.requiresWatchdog)
    }
    func testInvalidInputsCannotWriteHardware() {
        let hardware = Hardware(), controller = controller(hardware)
        for config in [BatteryConfiguration(limit: 0), .init(limit: 101), .init(maximumTemperature: 46), .init(maximumTemperature: 29)] {
            XCTAssertNotNil(controller.execute(.enable, configuration: config, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0).error)
        }
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 0, sessionID: Self.session, snapshot: snapshot(), now: 0).error)
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testThermalActivationRequiresTemperature() {
        let hardware = Hardware(), controller = controller(hardware)
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(80, temperature: nil), now: 0).error)
        XCTAssertTrue(hardware.writes.isEmpty)
        XCTAssertTrue(controller.execute(.enable, configuration: .init(thermalProtection: false), uid: 501, sessionID: Self.session, snapshot: snapshot(80, temperature: nil), now: 0).active)
    }
    func testWatchdogRestoresChargeWithoutAppOrOpenWindow() {
        let hardware = Hardware(), controller = controller(hardware)
        XCTAssertTrue(controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 10).suspended)
        XCTAssertEqual(hardware.value, 2)
        XCTAssertFalse(controller.tick(snapshot: snapshot(), now: 100).active)
        XCTAssertEqual(hardware.value, 0)
        XCTAssertFalse(controller.requiresWatchdog)
    }
    func testStatusDoesNotRenewLeaseAndLateHeartbeatCannotReviveIt() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        _ = controller.execute(.status, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 89)
        let late = controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 91)
        XCTAssertFalse(late.active); XCTAssertNil(late.error, "Lateness is not a fault"); XCTAssertEqual(hardware.value, 0)
    }
    func testHeartbeatRenewsOnlyForOwner() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        XCTAssertNotNil(controller.execute(.disable, configuration: nil, uid: 502, sessionID: Self.session, snapshot: snapshot(), now: 10).error)
        XCTAssertEqual(hardware.value, 2)
        _ = controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 80)
        XCTAssertTrue(controller.tick(snapshot: snapshot(), now: 100).active)
        XCTAssertFalse(controller.tick(snapshot: snapshot(), now: 170).active)
    }
    func testSleepRestoresChargeAndWakeReevaluatesPolicy() throws {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        try controller.prepareForSleep()
        XCTAssertEqual(hardware.value, 0)
        XCTAssertFalse(controller.tick(snapshot: snapshot(), now: 1).suspended)
        controller.didWake(now: 2)
        _ = controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 2)
        XCTAssertTrue(controller.tick(snapshot: snapshot(), now: 2).suspended)
    }
    func testTopUpReturnsToLimitAfterFullChargeOrUnplug() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        let topUp = controller.execute(.topUp, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 1)
        XCTAssertTrue(topUp.topUp); XCTAssertFalse(topUp.suspended); XCTAssertEqual(hardware.value, 0)
        let full = controller.tick(snapshot: snapshot(100), now: 2)
        XCTAssertFalse(full.topUp); XCTAssertTrue(full.suspended)
        _ = controller.execute(.topUp, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(90), now: 3)
        let unplugged = controller.tick(snapshot: snapshot(90, onAC: false), now: 4)
        XCTAssertFalse(unplugged.topUp); XCTAssertFalse(unplugged.suspended)
    }
    func testDisableAndLostMeasurementsRestoreHardware() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        XCTAssertFalse(controller.execute(.disable, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 1).active)
        XCTAssertEqual(hardware.value, 0)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 2)
        XCTAssertFalse(controller.tick(snapshot: .init(percent: nil), now: 3).active)
        XCTAssertEqual(hardware.value, 0)
    }
    func testRecoveryMarkerPrecedesWritesAndFailurePreventsActivation() {
        let hardware = Hardware()
        var marked = false
        let controller = BatteryProtectionController(hardware: hardware, markRecovery: { _ in
            XCTAssertTrue(hardware.writes.isEmpty)
            marked = true
        }, clearRecovery: { marked = false })
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        XCTAssertTrue(marked)
        _ = controller.execute(.disable, configuration: nil, uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 1)
        XCTAssertFalse(marked)
        let broken = BatteryProtectionController(hardware: hardware, markRecovery: { _ in throw Failure() }, clearRecovery: {})
        let count = hardware.writes.count
        XCTAssertFalse(broken.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 2).active)
        XCTAssertEqual(hardware.writes.count, count)
    }
    func testFailedRestoreKeepsWatchdogUntilRecoverySucceeds() {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        hardware.failWrites = true
        let failed = controller.tick(snapshot: snapshot(), now: 91)
        XCTAssertNotNil(failed.error); XCTAssertTrue(controller.requiresWatchdog)
        hardware.failWrites = false
        XCTAssertFalse(controller.tick(snapshot: snapshot(), now: 96).active)
        XCTAssertEqual(hardware.value, 0)
    }
    func testDoesNotTakeOverAnAlreadySuspendedBattery() {
        let hardware = Hardware(); hardware.value = 2
        let controller = controller(hardware)
        XCTAssertNotNil(controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0).error)
        XCTAssertTrue(hardware.writes.isEmpty)
    }
    func testDaemonShutdownRestoresCharge() throws {
        let hardware = Hardware(), controller = controller(hardware)
        _ = controller.execute(.enable, configuration: .init(), uid: 501, sessionID: Self.session, snapshot: snapshot(), now: 0)
        try controller.shutdown()
        XCTAssertEqual(hardware.value, 0)
        XCTAssertFalse(controller.requiresWatchdog)
    }
    func testCrashRecoveryRestoresChargeBeforeClearingMarker() throws {
        let hardware = Hardware(); hardware.value = 2
        var cleared = false
        let controller = BatteryProtectionController(hardware: hardware, markRecovery: { _ in }, clearRecovery: {
            XCTAssertEqual(hardware.value, 0); cleared = true
        })
        try controller.recover(.init(backend: .legacyPair))
        XCTAssertTrue(cleared)
    }
    func testTelemetryHandlesNestedCapacityAndMissingSensors() {
        let snapshot = BatterySnapshot.decode([
            "CurrentCapacity": 73, "MaxCapacity": 100, "CycleCount": 592,
            "BatteryData": ["FullChargeCapacity": 4409, "DesignCapacity": 5103],
            "ExternalConnected": true, "IsCharging": false
        ], appleSilicon: true)
        XCTAssertEqual(snapshot.percent, 73); XCTAssertEqual(snapshot.healthPercent, 86)
        XCTAssertEqual(snapshot.cycles, 592); XCTAssertTrue(snapshot.onAC)
        XCTAssertNil(snapshot.temperature)
        XCTAssertEqual(BatterySnapshot.decode(["Temperature": 3525], appleSilicon: true).temperature, 35.25)
        XCTAssertNil(BatterySnapshot.decode(["CurrentCapacity": 3, "MaxCapacity": 0], appleSilicon: true).percent)
        XCTAssertNil(BatterySnapshot.decode(["Temperature": 65535], appleSilicon: true).temperature)
    }
    @MainActor func testBatteryHasDedicatedNavigationAndStartsWithoutProtection() {
        XCTAssertEqual(Module.battery.section, .battery)
        XCTAssertEqual(NavigationSection.battery.destinations, [.battery])
        let suite = "MacCareBatteryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BatteryModel(defaults: defaults, monitor: false)
        XCTAssertFalse(model.active); XCTAssertEqual(model.configuration.limit, 80)
        XCTAssertTrue(model.configuration.thermalProtection)
    }
}
