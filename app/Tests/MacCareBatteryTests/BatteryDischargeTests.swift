import Foundation
import Testing
import MacCareBattery

struct BatteryDischargeTests {
    private final class Events { var values: [String] = [] }
    private final class Base: ChargeHardware {
        let events: Events
        var value: UInt8 = 0
        var capabilities = BatteryControlCapabilities(backend: .chargeGate)
        init(_ events: Events) { self.events = events }
        func readSwitch() throws -> UInt8 { value }
        func writeSwitch(_ value: UInt8) throws { self.value = value; events.values.append("gate") }
        func restore(_ record: BatteryRecoveryRecord) throws { value = 0; events.values.append("restore-charge") }
        func captureRecovery() throws -> BatteryRecoveryRecord { .init(backend: .chargeGate) }
    }
    private final class Adapter: PowerAdapterDriver {
        let events: Events
        var disabled = false
        var writes: [Bool] = []
        init(_ events: Events) { self.events = events }
        func discover() throws -> BatteryAdapterBackend { .modern }
        func read(_ backend: BatteryAdapterBackend) throws -> Bool { disabled }
        func write(_ backend: BatteryAdapterBackend, disabled: Bool) throws {
            self.disabled = disabled; writes.append(disabled); events.values.append(disabled ? "isolate" : "restore-adapter")
        }
    }
    @Test func isolationIsDurableAndEndsAtTargetWithoutDependingOnLogicalAC() throws {
        let events = Events()
        let adapter = Adapter(events)
        let hardware = RecoverableChargeHardware(base: Base(events), adapter: adapter, identity: { "fixture" })
        var pending: BatteryRecoveryRecord?
        let controller = BatteryProtectionController(hardware: hardware, markRecovery: { pending = $0 }, clearRecovery: { pending = nil })
        let session = UUID()
        func execute(_ command: BatteryCommand, _ percent: Int, _ ac: Bool, _ now: Double) -> BatteryProtectionStatus {
            controller.execute(command, configuration: .init(limit: 70, thermalProtection: false), uid: 501, sessionID: session,
                               snapshot: .init(percent: percent, onAC: ac, temperature: 25), now: now)
        }
        #expect(execute(.enable, 80, true, 0).active)
        #expect(pending?.adapterBackend == .modern)
        #expect(pending?.version == 3)
        #expect(execute(.discharge, 80, true, 1).cycle?.target == 70)
        #expect(adapter.disabled)
        _ = execute(.heartbeat, 75, false, 2)
        #expect(adapter.disabled)
        _ = execute(.heartbeat, 70, false, 3)
        #expect(adapter.disabled == false)
        #expect(adapter.writes == [true, false])
        #expect(pending != nil)
        #expect(execute(.disable, 70, true, 4).active == false)
        #expect(pending == nil)
    }
    @Test func watchdogRestoresAdapterBeforeChargeAndForeignRecordsCannotWrite() throws {
        let events = Events()
        let adapter = Adapter(events)
        let hardware = RecoverableChargeHardware(base: Base(events), adapter: adapter, identity: { "fixture" })
        let record = try hardware.captureRecovery()
        try hardware.setDischarging(true)
        let foreign = BatteryRecoveryRecord(backend: .chargeGate, machineID: "other", adapterBackend: .modern)
        #expect(throws: BatteryHardwareError.self) { try hardware.restore(foreign) }
        #expect(adapter.disabled)
        try hardware.restore(record)
        #expect(adapter.disabled == false)
        #expect(events.values == ["isolate", "restore-adapter", "restore-charge"])
        #expect(adapter.writes == [true, false])
    }
    @Test(arguments: [Double.nan, -1.0, BatteryCycle.dischargePhaseLimit]) func invalidOrExpiredCycleRefusesIsolation(now: Double) {
        var cycle = BatteryCycle(target: 70, now: 0)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: 80, onAC: true, temperature: 25), now: now) }
    }
    @Test func unknownTemperatureAndUnexpectedStateStopCycle() {
        var cycle = BatteryCycle(target: 70, now: 0)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: 80, onAC: true), now: 1) }
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: 80, onAC: true, temperature: 45), now: 1) }
    }
    @Test func existingIsolationCannotBeAdopted() {
        let events = Events()
        let adapter = Adapter(events); adapter.disabled = true
        let hardware = RecoverableChargeHardware(base: Base(events), adapter: adapter, identity: { "fixture" })
        #expect(throws: BatteryHardwareError.self) { try hardware.captureRecovery() }
        #expect(adapter.writes.isEmpty)
    }
    @Test func adapterSupportPreservesTheChargeControllerRestriction() {
        let events = Events(), base = Base(Events())
        base.capabilities = .init(backend: .nativeLimit, limitation: .hardwareAccessDenied)
        let hardware = RecoverableChargeHardware(base: base, adapter: Adapter(events), identity: { "fixture" })
        #expect(hardware.capabilities.limitation == .hardwareAccessDenied)
        #expect(hardware.capabilities.supportsDischarge)
        #expect(hardware.capabilities.supportsSailing == false)
        #expect(hardware.capabilities.supportedLimits == Array(80...100))
        #expect(events.values.isEmpty)
    }
    @Test func expiredLeaseRestoresAnIsolatedAdapterWithoutAnotherHeartbeat() throws {
        let events = Events(), adapter = Adapter(Events())
        let hardware = RecoverableChargeHardware(base: Base(events), adapter: adapter, identity: { "fixture" })
        var pending: BatteryRecoveryRecord?
        let controller = BatteryProtectionController(hardware: hardware, markRecovery: { pending = $0 }, clearRecovery: { pending = nil })
        let session = UUID(), snapshot = BatterySnapshot(percent: 80, onAC: true, temperature: 28)
        _ = controller.execute(.enable, configuration: .init(limit: 70, thermalProtection: false), uid: 501, sessionID: session, snapshot: snapshot, now: 0)
        _ = controller.execute(.discharge, configuration: nil, uid: 501, sessionID: session, snapshot: snapshot, now: 1)
        #expect(adapter.disabled)
        let expired = controller.tick(snapshot: .init(percent: 78, onAC: false, temperature: 28), now: 92)
        #expect(expired.active == false)
        #expect(expired.restoring == false)
        #expect(adapter.disabled == false)
        #expect(pending == nil)
        #expect(expired.cycle == nil)
    }

}
