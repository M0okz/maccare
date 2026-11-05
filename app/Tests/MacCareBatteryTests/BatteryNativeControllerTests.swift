import Foundation
import Testing
import MacCareBattery

struct BatteryNativeControllerTests {
    private enum Failure: Error, Equatable { case persistence, limit, restoration, unexpectedSwitch }

    private final class Journal {
        var pending: BatteryRecoveryRecord?
        var saved: [BatteryRecoveryRecord] = []
        var failSave = false
        var beforeClear: (() -> Void)?
        func save(_ record: BatteryRecoveryRecord) throws {
            if failSave { throw Failure.persistence }
            pending = record; saved.append(record)
        }
        func clear() {
            beforeClear?()
            pending = nil
        }
    }

    private final class Hardware: ChargeHardware {
        var capabilities = BatteryControlCapabilities(backend: .nativeLimit)
        var state: NativeChargeState
        var captures = 0
        var preparations = 0
        var restores = 0
        var ended = false
        var mutations: [NativeChargeState] = []
        var switchWrites: [UInt8] = []
        var failRestoration = false
        var failAfterMutation = false
        var capturedRecord: BatteryRecoveryRecord?
        var beforeMutation: (() -> Void)?
        init(_ state: NativeChargeState) { self.state = state }
        func readSwitch() throws -> UInt8 { state.enabled ? 2 : 0 }
        func writeSwitch(_ value: UInt8) throws {
            switchWrites.append(value)
            throw Failure.unexpectedSwitch
        }
        func captureRecovery() throws -> BatteryRecoveryRecord {
            captures += 1
            return capturedRecord ?? .init(backend: .nativeLimit, nativeState: state)
        }
        func prepareForControl() throws { preparations += 1 }
        func setChargeLimit(_ limit: Int?) throws {
            let target = limit ?? 100
            let requested = NativeChargeState(enabled: target < 100, limit: target)
            guard requested != state else { return }
            beforeMutation?()
            mutations.append(requested); state = requested
            if failAfterMutation { failAfterMutation = false; throw Failure.limit }
        }
        func restore(_ record: BatteryRecoveryRecord) throws {
            restores += 1
            if failRestoration { throw Failure.restoration }
            guard let original = record.nativeState, original != state else { return }
            beforeMutation?()
            mutations.append(original); state = original
        }
        func endSession() { ended = true }
    }

    private struct Fixture {
        let hardware: Hardware
        let journal: Journal
        let controller: BatteryProtectionController
        let session = UUID()
        init(initial: NativeChargeState = .init(enabled: false, limit: 100)) {
            let hardware = Hardware(initial), journal = Journal()
            hardware.beforeMutation = { #expect(journal.pending != nil, "Persist restoration state before every mutation") }
            self.hardware = hardware; self.journal = journal
            controller = .init(hardware: hardware, markRecovery: { try journal.save($0) }, clearRecovery: { journal.clear() })
        }
        func execute(_ command: BatteryCommand, limit: Int = 80, thermal: Bool = false,
                     percent: Int = 80, onAC: Bool = true, now: TimeInterval = 0) -> BatteryProtectionStatus {
            controller.execute(command, configuration: command == .enable ? .init(limit: limit, thermalProtection: thermal) : nil,
                               uid: 501, sessionID: session, snapshot: .init(percent: percent, onAC: onAC, temperature: 30), now: now)
        }
    }

    @Test(arguments: [79, 80, 100, 101])
    func nativeLimitsAreValidatedBeforeMutation(limit: Int) {
        let fixture = Fixture()
        let result = fixture.execute(.enable, limit: limit)
        let valid = (80...100).contains(limit)
        #expect(result.active == valid)
        #expect((result.error == nil) == valid)
        if valid {
            #expect(fixture.hardware.state == .init(enabled: limit < 100, limit: limit))
            #expect(fixture.journal.saved.count == 1)
        } else {
            #expect(fixture.hardware.captures == 0)
            #expect(fixture.hardware.mutations.isEmpty)
            #expect(fixture.journal.saved.isEmpty)
        }
        #expect(fixture.hardware.switchWrites.isEmpty)
    }

    @Test func unsupportedThermalPauseNeverTouchesNativeSettings() {
        let fixture = Fixture()
        let result = fixture.execute(.enable, thermal: true)
        #expect(result.active == false)
        #expect(result.error != nil)
        #expect(fixture.hardware.captures == 0)
        #expect(fixture.hardware.mutations.isEmpty)
    }

    @Test func statusNeverWritesOrRenewsNativeProtection() throws {
        let fixture = Fixture()
        #expect(fixture.execute(.status).capabilities?.backend == .nativeLimit)
        #expect(fixture.hardware.mutations.isEmpty)
        try #require(fixture.execute(.enable).active)
        let mutations = fixture.hardware.mutations
        let expired = fixture.execute(.status, percent: 100, now: 100)
        #expect(expired.active == false)
        #expect(expired.restoring)
        #expect(fixture.hardware.mutations == mutations)
        #expect(fixture.controller.requiresWatchdog)
    }

    @Test func persistenceFailurePreventsPreparationAndMutation() {
        let fixture = Fixture()
        fixture.journal.failSave = true
        let result = fixture.execute(.enable)
        #expect(result.active == false)
        #expect(result.error != nil)
        #expect(fixture.hardware.preparations == 0)
        #expect(fixture.hardware.mutations.isEmpty)
        #expect(fixture.hardware.ended)
        #expect(fixture.controller.requiresWatchdog == false)
    }

    @Test func changedBackendDuringCaptureCannotPersistOrMutate() {
        let fixture = Fixture()
        fixture.hardware.capturedRecord = .init(backend: .legacyPair)
        let result = fixture.execute(.enable)
        #expect(result.active == false)
        #expect(result.error != nil)
        #expect(fixture.hardware.preparations == 0)
        #expect(fixture.hardware.mutations.isEmpty)
        #expect(fixture.journal.pending == nil)
        #expect(fixture.hardware.ended)
    }

    @Test(arguments: [NativeChargeState(enabled: false, limit: 100), .init(enabled: true, limit: 85)])
    func disableRestoresExactInitialState(initial: NativeChargeState) throws {
        let fixture = Fixture(initial: initial)
        fixture.journal.beforeClear = { #expect(fixture.hardware.state == initial) }
        defer { fixture.journal.beforeClear = nil }
        try #require(fixture.execute(.enable).active)
        #expect(fixture.journal.saved.first?.nativeState == initial)
        #expect(fixture.journal.saved.first?.version == 2)
        let disabled = fixture.execute(.disable, now: 1)
        #expect(disabled.active == false)
        #expect(disabled.restoring == false)
        #expect(fixture.hardware.state == initial)
        #expect(fixture.hardware.switchWrites.isEmpty)
        #expect(fixture.journal.pending == nil)
    }

    @Test func ambiguousMutationFailureOnlyRestoresTheOriginalBackend() {
        let initial = NativeChargeState(enabled: true, limit: 90)
        let fixture = Fixture(initial: initial)
        fixture.hardware.failAfterMutation = true
        let failed = fixture.execute(.enable)
        #expect(failed.active == false)
        #expect(failed.error != nil)
        #expect(fixture.hardware.mutations == [.init(enabled: true, limit: 80), initial])
        #expect(fixture.hardware.state == initial)
        #expect(fixture.hardware.switchWrites.isEmpty)
        #expect(fixture.controller.requiresWatchdog == false)
    }

    @Test func aRenewalThatComesTooLateIsNotAFault() throws {
        let late = Fixture()
        try #require(late.execute(.enable).active)
        let expired = late.execute(.heartbeat, now: BatteryProtectionController.leaseDuration + 1)
        #expect(expired.active == false && expired.error == nil)
        let restoring = Fixture()
        try #require(restoring.execute(.enable).active)
        restoring.hardware.failRestoration = true
        _ = restoring.controller.tick(snapshot: .init(percent: 90), now: BatteryProtectionController.leaseDuration + 1)
        restoring.hardware.failRestoration = false
        #expect(restoring.execute(.heartbeat, now: BatteryProtectionController.leaseDuration + 2).active == false)
    }
    @Test func failedRestorationNeverResumesTheNativePolicy() throws {
        let initial = NativeChargeState(enabled: false, limit: 100)
        let fixture = Fixture(initial: initial)
        try #require(fixture.execute(.enable).active)
        fixture.hardware.failRestoration = true
        let failed = fixture.execute(.disable, now: 1)
        #expect(failed.active == false)
        #expect(failed.restoring)
        let mutations = fixture.hardware.mutations
        let heartbeat = fixture.execute(.heartbeat, now: 2)
        #expect(heartbeat.active == false)
        #expect(heartbeat.restoring)
        #expect(fixture.hardware.mutations == mutations)
        #expect(fixture.journal.pending != nil)
        fixture.hardware.failRestoration = false
        let restored = fixture.controller.tick(snapshot: .init(percent: 90), now: 3)
        #expect(restored.restoring == false)
        #expect(restored.active == false)
        #expect(fixture.hardware.state == initial)
        #expect(fixture.journal.pending == nil)
    }

    @Test func crashRecoveryRestoresEnabledNativeLimitBeforeClearingJournal() throws {
        let initial = NativeChargeState(enabled: true, limit: 85)
        let fixture = Fixture(initial: .init(enabled: true, limit: 80))
        let record = BatteryRecoveryRecord(backend: .nativeLimit, nativeState: initial)
        fixture.journal.pending = record
        fixture.journal.beforeClear = { #expect(fixture.hardware.state == initial) }
        defer { fixture.journal.beforeClear = nil }
        try fixture.controller.recover(record)
        #expect(fixture.hardware.state == initial)
        #expect(fixture.journal.pending == nil)
        #expect(fixture.controller.requiresWatchdog == false)
        #expect(fixture.hardware.captures == 0)
    }

    @Test func failedCrashRecoveryKeepsItsExactNativeRecordForRetry() {
        let initial = NativeChargeState(enabled: false, limit: 100)
        let fixture = Fixture(initial: .init(enabled: true, limit: 80))
        let record = BatteryRecoveryRecord(backend: .nativeLimit, nativeState: initial)
        fixture.journal.pending = record
        fixture.hardware.failRestoration = true
        #expect(throws: Failure.restoration) { try fixture.controller.recover(record) }
        #expect(fixture.controller.requiresWatchdog)
        #expect(fixture.journal.pending == record)
        fixture.hardware.failRestoration = false
        let restored = fixture.controller.tick(snapshot: .init(percent: 80), now: 0)
        #expect(restored.active == false)
        #expect(restored.restoring == false)
        #expect(fixture.hardware.state == initial)
        #expect(fixture.journal.pending == nil)
    }

    @Test func sleepRestoresAndOnlyFreshHeartbeatReappliesNativeLimit() throws {
        let initial = NativeChargeState(enabled: false, limit: 100)
        let fixture = Fixture(initial: initial)
        try #require(fixture.execute(.enable).active)
        try fixture.controller.prepareForSleep()
        #expect(fixture.hardware.state == initial)
        fixture.hardware.capabilities = .init(backend: .legacyPair)
        fixture.controller.didWake(now: 1_000)
        let mutations = fixture.hardware.mutations
        _ = fixture.controller.tick(snapshot: .init(percent: 90), now: 1_001)
        _ = fixture.execute(.status, now: 1_002)
        #expect(fixture.hardware.mutations == mutations)
        try #require(fixture.execute(.heartbeat, now: 1_003).active)
        #expect(fixture.hardware.state == .init(enabled: true, limit: 80))
    }

    @Test func wakingWithoutHeartbeatLeavesOriginalStateAndEndsSession() throws {
        let initial = NativeChargeState(enabled: true, limit: 95)
        let fixture = Fixture(initial: initial)
        try #require(fixture.execute(.enable).active)
        try fixture.controller.prepareForSleep()
        fixture.controller.didWake(now: 1_000)
        let mutations = fixture.hardware.mutations
        let expired = fixture.controller.tick(snapshot: .init(percent: 90), now: 1_015)
        #expect(expired.active == false)
        #expect(fixture.hardware.mutations == mutations)
        #expect(fixture.hardware.state == initial)
        #expect(fixture.journal.pending == nil)
    }

    @Test func topUpAndCancelPreserveTheOriginalNativeRestorationRecord() throws {
        let initial = NativeChargeState(enabled: true, limit: 85)
        let fixture = Fixture(initial: initial)
        try #require(fixture.execute(.enable).active)
        try #require(fixture.execute(.topUp, now: 1).topUp)
        #expect(fixture.hardware.state == .init(enabled: false, limit: 100))
        #expect(fixture.execute(.cancelTopUp, now: 2).topUp == false)
        #expect(fixture.hardware.state == .init(enabled: true, limit: 80))
        #expect(fixture.journal.saved.count == 1)
        _ = fixture.execute(.disable, now: 3)
        #expect(fixture.hardware.state == initial)
    }

    @Test func changingDiscoveryCannotReplaceActiveNativeCapabilities() throws {
        let fixture = Fixture()
        try #require(fixture.execute(.enable).active)
        fixture.hardware.capabilities = .init(backend: .legacyPair)
        let status = fixture.execute(.status, now: 1)
        #expect(status.capabilities?.backend == .nativeLimit)
        #expect(status.capabilities?.supportsThermalProtection == false)
        #expect(status.firmwareManaged == false)
        _ = fixture.execute(.enable, limit: 90, now: 2)
        #expect(fixture.hardware.state == .init(enabled: true, limit: 90))
        #expect(fixture.hardware.switchWrites.isEmpty)
    }

    @Test func unavailableLimitFromCapabilitySetCannotBeApplied() {
        let fixture = Fixture()
        fixture.hardware.capabilities = .init(backend: .nativeLimit, supportedLimits: [85, 100])
        #expect(fixture.execute(.enable, limit: 80).active == false)
        #expect(fixture.hardware.mutations.isEmpty)
        #expect(fixture.execute(.enable, limit: 85).active)
    }

    @Test(arguments: [
        BatteryControlCapabilities(backend: .nativeLimit, supportedLimits: []),
        .init(backend: .nativeLimit, supportedLimits: [80, 80, 100]),
        .init(backend: .nativeLimit, supportedLimits: [100, 80]),
        .init(backend: .nativeLimit, supportedLimits: [79, 100]),
        .init(backend: .nativeLimit, supportsThermalProtection: true)
    ])
    func malformedCapabilitiesCannotStartProtection(capabilities: BatteryControlCapabilities) {
        let fixture = Fixture()
        fixture.hardware.capabilities = capabilities
        let result = fixture.execute(.enable)
        #expect(result.active == false)
        #expect(result.error != nil)
        #expect(fixture.hardware.captures == 0)
        #expect(fixture.hardware.mutations.isEmpty)
    }

    @Test func nativeRecordRejectsMixedOrMissingRecoveryState() {
        #expect(BatteryRecoveryRecord(backend: .nativeLimit).isValid == false)
        #expect(BatteryRecoveryRecord(backend: .nativeLimit, nativeState: .init(enabled: true, limit: 79)).isValid == false)
        #expect(BatteryRecoveryRecord(backend: .nativeLimit, nativeState: .init(enabled: true, limit: 101)).isValid == false)
        #expect(BatteryRecoveryRecord(backend: .nativeLimit, firmwareUpper: 100,
                                      nativeState: .init(enabled: true, limit: 80)).isValid == false)
        #expect(BatteryRecoveryRecord(backend: .legacyPair, nativeState: .init(enabled: false, limit: 100)).isValid)
    }

    @Test(arguments: [
        #"{"version":1,"machineID":"fixture","backend":1}"#,
        #"{"version":1,"machineID":"fixture","backend":2}"#,
        #"{"version":1,"machineID":"fixture","backend":3,"firmwareUpper":95,"firmwareLower":90}"#
    ])
    func legacyRecordsDecodeWithoutNewNativeField(json: String) throws {
        let record = try JSONDecoder().decode(BatteryRecoveryRecord.self, from: Data(json.utf8))
        #expect(record.isValid)
        #expect(record.version == 1)
        #expect(record.nativeState == nil)
        if record.backend == .firmware {
            #expect(record.firmwareUpper == 95)
            #expect(record.firmwareLower == 90)
        }
    }

    @Test func legacyStatusDecodesWithoutNewOptionalCapabilities() throws {
        let encoded = try JSONEncoder().encode(BatteryProtectionStatus(snapshot: .init(percent: 80)))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "capabilities")
        let oldStatus = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(BatteryProtectionStatus.self, from: oldStatus).capabilities == nil)
    }

    @Test func nativeVersionOneAndUnknownRecordVersionsAreInvalid() throws {
        for version in [1, 3] {
            let json = "{\"version\":\(version),\"machineID\":\"fixture\",\"backend\":4,\"nativeState\":{\"enabled\":true,\"limit\":80}}"
            let record = try JSONDecoder().decode(BatteryRecoveryRecord.self, from: Data(json.utf8))
            #expect(record.isValid == false)
        }
    }
}
