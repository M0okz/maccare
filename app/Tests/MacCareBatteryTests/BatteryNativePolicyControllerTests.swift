import Foundation
import IOKit
import Testing
@testable import MacCareBattery

struct BatteryNativePolicyControllerTests {
    private enum Failure: Error { case persistence, write, clear, read }
    private class Driver: NativeChargePolicyDriver {
        var isAvailable = true
        var preferences: NativeChargePolicyPreferences
        var registered: Int?
        var override: Bool? = false
        var automaticallyRegister = true
        var failWrite = false
        var failClear = false
        var failRead = false
        var targets: [Int] = []
        var clears = 0
        var restores = 0
        var beforeMutation: (() -> Void)?
        init(_ original: NativeChargePolicyPreferences) {
            preferences = original
            if original.featureEnabled == true, case .integer(let limit) = original.limit { registered = limit }
        }
        func readPreferences() throws -> NativeChargePolicyPreferences {
            if failRead { throw Failure.read }; return preferences
        }
        func apply(limit: Int) throws {
            beforeMutation?(); targets.append(limit)
            preferences = .init(featureState: .integer(1), limit: failWrite ? .absent : .integer(limit))
            if failWrite { failWrite = false; throw Failure.write }
            if automaticallyRegister { registered = limit }
        }
        func clearRegisteredLimit() throws {
            beforeMutation?(); clears += 1
            if failClear { throw Failure.clear }
            registered = nil
            preferences = .init(featureState: .integer(0), limit: preferences.limit)
        }
        func restorePreferences(_ snapshot: NativeChargePolicyPreferences) throws {
            beforeMutation?(); restores += 1; preferences = snapshot
            if automaticallyRegister, snapshot.featureEnabled == true, case .integer(let limit) = snapshot.limit { registered = limit }
        }
        func registeredLimit() throws -> Int? { registered }
        func calibrationOverride() -> Bool? { override }
    }
    /// Simulates Apple's >5-point automatic refill and a latch reset only by a consumed release.
    private final class FirmwareDriver: Driver {
        var percent = 80
        var charging = false
        var latched = true
        var deferRelease = false
        var releaseQueued = false
        func drift(to percent: Int) {
            self.percent = percent
            if let registered, latched && percent < registered - 5 { latched = false; charging = true }
        }
        override func apply(limit: Int) throws {
            // Reapplying before release consumption cancels that release in this conservative model.
            if releaseQueued { releaseQueued = false }
            try super.apply(limit: limit)
            if percent >= limit { latched = true; charging = false }
            else if !latched { charging = true }
        }
        override func clearRegisteredLimit() throws {
            if deferRelease {
                beforeMutation?(); clears += 1; releaseQueued = true
                preferences = .init(featureState: .integer(0), limit: preferences.limit)
            } else {
                try super.clearRegisteredLimit(); latched = false; charging = true
            }
        }
        func consumeRelease() { registered = nil; releaseQueued = false; latched = false; charging = true }
    }
    private final class Adapter: PowerAdapterDriver {
        var disabled = false
        var writes: [Bool] = []
        var failRelease = false
        var renegotiating = false
        var journal: Journal?
        func discover() throws -> BatteryAdapterBackend { .modern }
        func read(_ backend: BatteryAdapterBackend) throws -> Bool {
            if renegotiating { throw BatteryHardwareError(code: kIOReturnUnsupported) }
            return disabled
        }
        func write(_ backend: BatteryAdapterBackend, disabled value: Bool) throws {
            #expect(journal?.pending?.adapterBackend == .modern, "The gate must be restorable before it is touched")
            if !value && failRelease { failRelease = false; throw Failure.write }
            disabled = value; writes.append(value)
        }
    }
    private final class Journal {
        var pending: BatteryRecoveryRecord?
        var failSave = false
        var failClear = false
        func save(_ record: BatteryRecoveryRecord) throws {
            if failSave { throw Failure.persistence }; pending = record
        }
        func clear() throws { if failClear { throw Failure.persistence }; pending = nil }
    }
    private final class Fixture {
        let driver: Driver
        let journal: Journal
        let adapter = Adapter()
        var pauses: [TimeInterval] = []
        var level: Int?
        let hardware: RecoverableChargeHardware
        let controller: BatteryProtectionController
        let session = UUID()
        init(original: NativeChargePolicyPreferences = .init(featureState: .absent, limit: .absent), driver injected: Driver? = nil) {
            let driver = injected ?? Driver(original), journal = Journal()
            self.driver = driver; self.journal = journal
            // An explicit fixed AC context keeps all tests independent of the host Mac.
            var recordPause: (TimeInterval) -> Void = { _ in }
            var readLevel: () -> Int? = { nil }
            let policy = NativeChargePolicyHardware(driver: driver, identity: { "fixture-M1" }, onAC: { true },
                                                    percent: { readLevel() }, adapter: adapter, pause: { recordPause($0) })
            let hardware = RecoverableChargeHardware(base: policy, adapter: adapter, identity: { "fixture-M1" })
            self.hardware = hardware
            adapter.journal = journal
            driver.beforeMutation = { #expect(journal.pending != nil, "The original policy must be durable before any write or release") }
            controller = .init(hardware: hardware, markRecovery: { try journal.save($0) }, clearRecovery: { try journal.clear() })
            recordPause = { [unowned self] in self.pauses.append($0) }
            readLevel = { [unowned self] in self.level }
        }
        func run(_ command: BatteryCommand, limit: Int = 70, sailing: Int? = nil, thermal: Bool = false,
                 percent: Int = 60, temperature: Double = 30, charging: Bool = false, onAC: Bool = true,
                 now: TimeInterval = 0) -> BatteryProtectionStatus {
            let snapshot = BatterySnapshot(percent: percent, onAC: onAC, charging: charging, temperature: temperature)
            return controller.execute(command, configuration: command == .enable
                ? .init(limit: limit, thermalProtection: thermal, maximumTemperature: 35, sailingWidth: sailing) : nil,
                uid: 501, sessionID: session, snapshot: snapshot, now: now)
        }
    }

    @Test func capturesAbsentKeysInVersionFiveBeforeWritingBelowEighty() throws {
        let f = Fixture()
        let result = f.run(.enable)
        #expect(result.active)
        #expect(result.capabilities?.backend == .nativePolicy)
        #expect(f.driver.targets == [70])
        let record = try #require(f.journal.pending)
        #expect(record.version == 5 && record.isValid && record.adapterBackend == .modern)
        #expect(record.nativePolicyPreferences == .init(featureState: .absent, limit: .absent))
        #expect(try JSONDecoder().decode(BatteryRecoveryRecord.self, from: JSONEncoder().encode(record)) == record)
    }
    @Test func eachWrittenTargetPulsesTheInputOnceAndReleasesIt() throws {
        let f = Fixture()
        try #require(f.run(.enable, limit: 70, percent: 60).active)
        #expect(f.adapter.writes == [true, false] && !f.adapter.disabled)
        #expect(f.pauses == [NativeChargePolicyHardware.inputPulseDuration])
        #expect(f.run(.heartbeat, limit: 70, percent: 60, now: 5).active)
        #expect(f.adapter.writes == [true, false], "A heartbeat without a change must not touch the input")
    }
    @Test func reachingARegisteredTargetPulsesWithoutRewritingIt() throws {
        let f = Fixture()
        try #require(f.run(.enable, limit: 70, percent: 69, charging: true).active)
        #expect(f.driver.targets == [70] && f.adapter.writes.count == 2)
        #expect(f.run(.heartbeat, percent: 70, charging: true, now: 5).active)
        #expect(f.driver.targets == [70], "The target is reached, not moved")
        #expect(f.adapter.writes == [true, false, true, false])
    }
    @Test func noPulseWithoutExternalPower() throws {
        let f = Fixture()
        try #require(f.run(.enable, limit: 70, percent: 60, onAC: false).active)
        #expect(f.driver.targets == [70] && f.adapter.writes.isEmpty)
    }
    @Test func failedPulseReleaseRestoresGateBeforeAnythingElse() throws {
        let f = Fixture(); f.adapter.failRelease = true
        let result = f.run(.enable, limit: 70, percent: 60)
        #expect(!result.active && result.error != nil)
        #expect(!f.adapter.disabled, "Restoration must give the input back")
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
        #expect(f.journal.pending == nil)
    }
    @Test func gateRenegotiatingAtReconnectSkipsThePulseWithoutEndingTheSession() throws {
        let f = Fixture(); try #require(f.run(.enable, limit: 70, percent: 70, onAC: false).active)
        f.adapter.renegotiating = true
        let reconnected = f.run(.heartbeat, percent: 71, onAC: true, now: 5)
        #expect(reconnected.active && reconnected.error == nil)
        #expect(f.driver.targets.last == 71, "The target is still written, only the pulse is skipped")
        #expect(f.adapter.writes.isEmpty)
    }
    @Test func aGateAlreadyClosedByAnotherControllerStillEndsTheSession() throws {
        let f = Fixture(); try #require(f.run(.enable, limit: 70, percent: 70, onAC: false).active)
        f.adapter.disabled = true
        let result = f.run(.heartbeat, percent: 71, onAC: true, now: 5)
        #expect(!result.active && result.error != nil)
        #expect(!f.adapter.disabled, "Restoration gives the input back")
    }
    @Test func versionFourJournalStaysRestorableWithoutTouchingTheGate() throws {
        let original = NativeChargePolicyPreferences(featureState: .absent, limit: .absent)
        let f = Fixture(original: original)
        let record = BatteryRecoveryRecord(backend: .nativePolicy, machineID: "fixture-M1", nativePolicyPreferences: original)
        #expect(record.version == 4 && record.isValid)
        f.journal.pending = record
        try f.controller.recover(record)
        #expect(f.adapter.writes.isEmpty && f.journal.pending == nil)
    }
    @Test func disablingAboveTheOriginalLimitNeverRegistersItUnderTheChargeLevel() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(80))
        let f = Fixture(original: original); f.level = 85
        try #require(f.run(.enable, limit: 85, percent: 85).active)
        #expect(f.driver.registered == 85)
        let off = f.run(.disable, percent: 85, now: 1)
        #expect(!off.active && off.restoring && off.error == nil)
        #expect(off.deferredRestorationTarget == 80 && off.message.contains("80 %"))
        #expect(f.driver.registered == 85 && f.driver.clears == 0 && f.journal.pending != nil)
        #expect(f.adapter.writes.count == 2, "Already holding at this level: no further write or pulse")
        // Still waiting while plugged in, and following the level down once it starts to fall.
        f.level = 84
        _ = f.controller.tick(snapshot: .init(percent: 84, onAC: false, temperature: 30), now: 5)
        #expect(f.driver.registered == 84 && f.journal.pending != nil)
        // The original comes back only once it is no longer under the level.
        f.level = 80
        let restored = f.controller.tick(snapshot: .init(percent: 80, onAC: false, temperature: 30), now: 10)
        #expect(!restored.restoring && restored.deferredRestorationTarget == nil && restored.error == nil)
        #expect(f.driver.preferences == original && f.driver.registered == 80 && f.journal.pending == nil)
    }
    @Test func enablingAgainDuringADeferredRestorationKeepsTheTrueOriginal() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(80))
        let f = Fixture(original: original); f.level = 85
        try #require(f.run(.enable, limit: 85, percent: 85).active)
        _ = f.run(.disable, percent: 85, now: 1)
        let again = f.run(.enable, limit: 85, percent: 85, now: 2)
        #expect(again.active && !again.restoring && again.deferredRestorationTarget == nil && again.ownedByCaller)
        #expect(f.journal.pending?.nativePolicyPreferences == original, "The journal is never overwritten with the temporary hold")
        f.level = 80
        _ = f.run(.disable, percent: 80, now: 3)
        #expect(f.driver.preferences == original && f.journal.pending == nil)
    }
    @Test func unknownLevelFallsBackToTheNormalRestoration() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(80))
        let f = Fixture(original: original); f.level = nil
        try #require(f.run(.enable, limit: 85, percent: 85).active)
        let off = f.run(.disable, percent: 85, now: 1)
        #expect(!off.restoring && f.driver.preferences == original && f.journal.pending == nil)
    }
    @Test func crashRecoveryAboveTheOriginalDefersWithoutReportingAFailure() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(80))
        let f = Fixture(original: original); f.level = 85
        let record = BatteryRecoveryRecord(backend: .nativePolicy, machineID: "fixture-M1", adapterBackend: .modern, nativePolicyPreferences: original)
        f.journal.pending = record
        try f.controller.recover(record)
        #expect(f.driver.registered == 85 && f.journal.pending != nil)
        let again = f.run(.enable, limit: 85, percent: 85, now: 1)
        #expect(again.active && again.ownedByCaller && again.error == nil, "Recovery leaves the gate and policy usable by a new session")
        #expect(again.capabilities?.supportsDischarge == true)
    }
    @Test func sleepDuringTopUpAboveTheOriginalDefersInsteadOfCuttingInput() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(80))
        let f = Fixture(original: original); f.level = 90
        try #require(f.run(.enable, limit: 85, percent: 85).active)
        try #require(f.run(.topUp, percent: 90, now: 1).active)
        try f.controller.prepareForSleep()
        #expect(f.driver.registered == 90 && f.journal.pending != nil)
        #expect(f.driver.preferences == .init(featureState: .integer(1), limit: .integer(90)))
    }
    @Test func inputLostRightAfterAChangeStopsInsteadOfWritingAgain() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 60).active)
        let targets = f.driver.targets
        let lost = f.run(.heartbeat, percent: 60, onAC: false, now: 5)
        #expect(!lost.active && lost.error == BatteryNativePolicyError.inputLost.errorDescription)
        #expect(f.driver.targets == targets, "No further target may be written after the loss")
        #expect(!f.adapter.disabled && f.journal.pending == nil)
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
    }
    @Test func unpluggingLaterIsNotTreatedAsAFault() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 60).active)
        let unplugged = f.run(.heartbeat, percent: 60, onAC: false, now: NativeChargePolicyHardware.inputLossWindow + 1)
        #expect(unplugged.active && unplugged.error == nil)
    }
    @Test func aHoldAboveTheLimitDoesNotClaimTheLimitWasReached() throws {
        let f = Fixture(); f.level = 85
        let above = f.run(.enable, limit: 80, percent: 85)
        #expect(above.message == "Charge suspendue · batterie au-dessus de la limite de 80 %")
        #expect(f.driver.targets == [85], "The level is held, never a target under it")
        let reached = f.run(.heartbeat, limit: 80, percent: 80, now: 5)
        #expect(reached.message == "Charge suspendue · limite de 80 % atteinte")
    }
    @Test func persistenceFailurePreventsAllMutations() {
        let f = Fixture(); f.journal.failSave = true
        #expect(!f.run(.enable).active)
        #expect(f.driver.targets.isEmpty && f.driver.clears == 0 && f.adapter.writes.isEmpty)
        #expect(!f.controller.requiresWatchdog)
    }
    @Test func loweringLimitHoldsAtObservedChargeAndFollowsNaturalDrift() {
        let f = Fixture()
        #expect(f.run(.enable, percent: 90).active)
        #expect(f.driver.targets == [90])
        #expect(f.run(.heartbeat, percent: 89, now: 10).active)
        #expect(f.driver.targets == [90, 89], "A hold follows the observed level without requesting a deliberate discharge below it")
    }
    @Test func sailingHoldsWithinBandThenChargesToUpper() {
        let f = Fixture()
        #expect(f.run(.enable, limit: 80, sailing: 5, percent: 78).active)
        #expect(f.driver.targets == [78])
        #expect(f.run(.heartbeat, percent: 77, now: 10).active)
        #expect(f.driver.targets == [78, 77])
        #expect(f.run(.heartbeat, percent: 75, now: 20).active)
        #expect(f.driver.targets == [78, 77, 80])
        #expect(f.driver.clears == 1, "Resume releases the old hold before registering the upper bound")
    }
    @Test func thermalHoldResumesOnlyAfterCoolingAndFiveMinutes() {
        let f = Fixture()
        #expect(f.run(.enable, limit: 80, thermal: true, percent: 60, temperature: 36).active)
        #expect(f.driver.targets == [60])
        for now in [60.0, 120, 180, 240, 299] {
            #expect(f.run(.heartbeat, percent: 60, temperature: 32, now: now).active)
        }
        #expect(f.driver.targets == [60])
        #expect(f.run(.heartbeat, percent: 60, temperature: 32, now: 300).active)
        #expect(f.driver.targets == [60, 80])
    }
    @Test func writtenPreferencesDoNotClaimRegisteredOrStoppedCharging() {
        let f = Fixture(); f.driver.automaticallyRegister = false
        let result = f.run(.enable, charging: true)
        #expect(result.active)
        #expect(result.chargeApplication?.requestedLimit == 70)
        #expect(result.chargeApplication?.registered == false)
        #expect(result.suspended == false)
        #expect(result.message.contains("en cours"))
    }
    @Test func missingRegistrationRestoresAfterGraceWithoutRenewingGraceOnRetries() {
        let f = Fixture(); f.driver.automaticallyRegister = false
        #expect(f.run(.enable).active)
        #expect(f.run(.heartbeat, now: 60).active)
        #expect(f.run(.heartbeat, now: 120).active)
        let result = f.run(.heartbeat, now: 150)
        #expect(!result.active && result.error != nil)
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
        #expect(f.journal.pending == nil)
    }
    @Test func reconnectGetsItsOwnRegistrationGrace() {
        let f = Fixture(); f.driver.automaticallyRegister = false
        #expect(f.run(.enable, onAC: false).active)
        for now in [60.0, 120, 180, 240] { #expect(f.run(.heartbeat, onAC: false, now: now).active) }
        let connected = f.run(.heartbeat, onAC: true, now: 250)
        #expect(connected.active)
        #expect(connected.chargeApplication?.elapsed == 0)
        f.driver.registered = 70
        #expect(f.run(.heartbeat, now: 300).chargeApplication?.registered == true)
    }
    @Test func statusNeverWritesOrRenewsLease() throws {
        let f = Fixture(); try #require(f.run(.enable).active)
        let targets = f.driver.targets
        let status = f.run(.status, now: 100)
        #expect(!status.active && status.restoring)
        #expect(f.driver.targets == targets && f.driver.clears == 0)
        #expect(f.journal.pending != nil)
    }
    @Test func failedPartialWriteRestoresAbsentKeys() {
        let f = Fixture(); f.driver.failWrite = true
        let result = f.run(.enable)
        #expect(!result.active && result.error != nil)
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
        #expect(f.journal.pending == nil)
    }
    @Test func restorationWaitsForOriginalTargetAndDoesNotClearItAgain() throws {
        let original = NativeChargePolicyPreferences(featureState: .boolean(true), limit: .integer(85))
        let f = Fixture(original: original)
        try #require(f.run(.enable).active)
        f.driver.automaticallyRegister = false
        let pending = f.run(.disable, now: 10)
        #expect(!pending.active && pending.restoring)
        #expect(pending.error == nil, "Expected propagation is progress, not a failure")
        #expect(f.journal.pending != nil && f.driver.preferences == original)
        #expect(f.driver.clears == 1)
        f.driver.registered = 85
        let restored = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 15)
        #expect(!restored.active && !restored.restoring)
        #expect(restored.error == nil, "Completed restoration must not retain a stale progress error")
        #expect(f.journal.pending == nil && f.driver.clears == 1)
    }
    @Test func clearFailureRetainsRecoveryForWatchdog() throws {
        let f = Fixture(); try #require(f.run(.enable).active)
        f.driver.failClear = true
        #expect(f.run(.disable, now: 10).restoring)
        #expect(f.journal.pending != nil)
        f.driver.failClear = false
        _ = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 15)
        #expect(f.journal.pending == nil)
    }
    @Test func expectedRestorationDelayDoesNotEraseAnEarlierWriteFailure() {
        let f = Fixture(original: .init(featureState: .integer(1), limit: .integer(85)))
        f.driver.automaticallyRegister = false; f.driver.failWrite = true
        let failed = f.run(.enable)
        #expect(failed.restoring && failed.error != nil)
        let pending = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 5)
        #expect(pending.restoring && pending.error == failed.error)
        f.driver.registered = 85
        let restored = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 10)
        #expect(!restored.restoring && restored.error == failed.error)
        #expect(f.journal.pending == nil)
    }
    @Test func calibrationDischargesThroughTheGateAndReopensItToRecharge() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 80).active)
        try #require(f.run(.calibrate, percent: 80, now: 1).cycle?.phase == .chargingToFull)
        let full = f.run(.heartbeat, percent: 100, now: 2)
        #expect(full.cycle?.phase == .dischargingForCalibration)
        #expect(f.driver.targets.last == 10 && f.adapter.disabled)
        let draining = f.run(.heartbeat, percent: 40, onAC: false, now: 3)
        #expect(draining.active && f.adapter.disabled)
        let low = f.run(.heartbeat, percent: 10, onAC: false, now: 4)
        #expect(low.cycle?.phase == .rechargingToFull)
        #expect(f.driver.targets.last == 100 && !f.adapter.disabled)
    }
    @Test func explicitDischargeClosesGateFirstThenReopensItWithTargetInPlace() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        let before = f.driver.targets.count
        var gateAtWrite: Bool?
        f.driver.beforeMutation = { [unowned f] in gateAtWrite = f.adapter.disabled }
        try #require(f.run(.discharge, percent: 90, now: 1).cycle != nil)
        #expect(f.driver.targets.last == 70 && f.driver.targets.count == before + 1)
        #expect(gateAtWrite == true, "A target under the charge level is never written with the gate open")
        // The closed gate makes the Mac report battery power. That is not an unplugged Mac.
        let draining = f.run(.heartbeat, percent: 85, onAC: false, now: 2)
        #expect(draining.active && draining.error == nil && f.adapter.disabled)
        #expect(f.driver.targets.last == 70 && f.driver.clears == 0)
        let finished = f.run(.heartbeat, percent: 70, onAC: false, now: 3)
        #expect(finished.active && finished.error == nil && finished.cycle == nil)
        #expect(!f.adapter.disabled && f.driver.targets.last == 70)
        #expect(f.driver.clears == 0, "Reaching the target does not release the limit it is held at")
        let holding = f.run(.heartbeat, percent: 70, now: 4)
        #expect(holding.active && holding.error == nil && f.driver.clears == 0 && f.driver.targets.last == 70)
        #expect(f.journal.pending != nil)
    }
    @Test func cancellingDischargeReopensTheGate() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        try #require(f.run(.discharge, percent: 90, now: 1).cycle != nil)
        let cancelled = f.run(.cancelCycle, percent: 85, onAC: false, now: 2)
        #expect(cancelled.active && cancelled.cycle == nil && !f.adapter.disabled)
    }
    @Test func disablingDuringDischargeReopensTheGateBeforeRestoringThePolicy() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        try #require(f.run(.discharge, percent: 90, now: 1).cycle != nil)
        var gateAtRestore: Bool?
        f.driver.beforeMutation = { [unowned f] in gateAtRestore = f.adapter.disabled }
        let off = f.run(.disable, percent: 85, onAC: false, now: 2)
        #expect(!off.active && !f.adapter.disabled && f.journal.pending == nil)
        #expect(gateAtRestore == false)
    }
    @Test func dischargeRefusedWithoutACAndWithoutAGate() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        #expect(f.run(.discharge, percent: 90, onAC: false, now: 1).cycle == nil)
        #expect(!f.adapter.disabled)
    }
    @Test func sleepKeepsTheLimitAndAHeartbeatResumesWithoutRewriting() throws {
        let f = Fixture(); try #require(f.run(.enable).active)
        let active = f.driver.preferences, targets = f.driver.targets, pulses = f.adapter.writes
        try f.controller.prepareForSleep()
        #expect(f.driver.preferences == active && f.driver.registered == 70)
        #expect(f.driver.clears == 0 && f.journal.pending != nil)
        f.controller.didWake(now: 200)
        #expect(f.run(.heartbeat, now: 201).active)
        #expect(f.driver.targets == targets && f.adapter.writes == pulses)
        _ = f.run(.disable, now: 202)
        #expect(f.driver.clears == 1 && f.journal.pending == nil)
    }
    @Test func appNotReturningAfterWakeRestoresTheOriginalLimit() throws {
        let f = Fixture(); try #require(f.run(.enable).active)
        try f.controller.prepareForSleep()
        f.controller.didWake(now: 200)
        let expired = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 200 + BatteryProtectionController.wakeGrace)
        #expect(!expired.active && f.journal.pending == nil)
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
    }
    @Test func sleepDuringDischargeReopensTheGateAndRestores() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        try #require(f.run(.discharge, percent: 90, now: 1).cycle != nil)
        #expect(f.adapter.disabled)
        try f.controller.prepareForSleep()
        #expect(!f.adapter.disabled && f.driver.clears == 1)
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
    }
    @Test func sleepDuringTopUpDoesNotLeaveTheFullTargetInPlace() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 60).active)
        #expect(f.run(.topUp, percent: 60, now: 1).active)
        #expect(f.driver.targets.last == 100)
        try f.controller.prepareForSleep()
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
    }
    @Test func journalClearFailureDoesNotClearRestoredOriginalAgain() throws {
        let original = NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(85))
        let f = Fixture(original: original); try #require(f.run(.enable).active)
        f.journal.failClear = true
        #expect(f.run(.disable, now: 1).restoring)
        #expect(f.driver.preferences == original && f.driver.registered == 85)
        #expect(f.driver.clears == 1 && f.driver.restores == 1 && f.journal.pending != nil)
        f.journal.failClear = false
        _ = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 2)
        #expect(f.driver.clears == 1 && f.driver.restores == 1 && f.journal.pending == nil)
    }
    @Test func widerSailingBandDoesNotUseFirmwaresEarlierRefillThreshold() throws {
        let driver = FirmwareDriver(.init(featureState: .absent, limit: .absent))
        let f = Fixture(driver: driver)
        try #require(f.run(.enable, limit: 80, sailing: 10, percent: 80).active)
        for percent in stride(from: 79, through: 71, by: -1) {
            driver.drift(to: percent)
            _ = f.run(.heartbeat, percent: percent, charging: driver.charging, now: Double(80 - percent) * 5)
            #expect(!driver.charging)
            #expect(driver.registered == percent)
            #expect(driver.targets.last == percent, "A hold never deliberately requests a target below the observed SOC")
        }
        driver.drift(to: 70)
        _ = f.run(.heartbeat, percent: 70, charging: driver.charging, now: 50)
        #expect(driver.charging && driver.registered == 80 && driver.clears == 1)
    }
    @Test func narrowSailingBandWaitsForReleaseBeforeRearmingCharge() throws {
        let driver = FirmwareDriver(.init(featureState: .absent, limit: .absent))
        let f = Fixture(driver: driver)
        try #require(f.run(.enable, limit: 80, sailing: 2, percent: 80).active)
        driver.drift(to: 79)
        _ = f.run(.heartbeat, percent: 79, now: 5)
        driver.deferRelease = true; driver.drift(to: 78)
        let pending = f.run(.heartbeat, percent: 78, now: 10)
        #expect(!driver.charging && driver.releaseQueued && driver.targets.last == 79)
        #expect(pending.chargeApplication?.releasePending == true)
        driver.consumeRelease()
        let resumed = f.run(.heartbeat, percent: 78, charging: driver.charging, now: 15)
        #expect(driver.charging && driver.targets.last == 80 && driver.clears == 1)
        #expect(resumed.chargeApplication?.releasePending == false)
    }
    @Test func thermalHoldTracksBatteryDrainInsteadOfAllowingFivePointRefill() throws {
        let driver = FirmwareDriver(.init(featureState: .absent, limit: .absent)); driver.percent = 50
        let f = Fixture(driver: driver)
        try #require(f.run(.enable, limit: 80, thermal: true, percent: 50, temperature: 36).active)
        for percent in stride(from: 49, through: 44, by: -1) {
            driver.drift(to: percent)
            _ = f.run(.heartbeat, percent: percent, temperature: 36, charging: driver.charging, now: Double(50 - percent) * 5)
            #expect(!driver.charging && driver.targets.last == percent)
        }
    }
    @Test func oldRegistrationOscillationCannotKeepRenewingGrace() {
        let f = Fixture(); f.driver.automaticallyRegister = false
        _ = f.run(.enable, limit: 70, percent: 80)
        f.driver.registered = 80
        _ = f.run(.heartbeat, percent: 79, now: 10)
        f.driver.registered = 79
        _ = f.run(.heartbeat, percent: 78, now: 20)
        for now in [50.0, 80, 110, 140] {
            f.driver.registered = now == 50 || now == 110 ? 80 : 79
            #expect(f.run(.heartbeat, percent: 71, now: now).active)
        }
        f.driver.registered = 80
        let failed = f.run(.heartbeat, percent: 71, now: 170)
        #expect(!failed.active && failed.error != nil)
    }
    @Test func inconsistentExistingRegistrationPreventsCaptureAndMutation() {
        let f = Fixture(); f.driver.registered = 80
        #expect(!f.run(.enable).active)
        #expect(f.driver.targets.isEmpty && f.driver.clears == 0 && f.journal.pending == nil)
    }
    @Test(arguments: [true, nil])
    func appleCalibrationOrUnknownOverrideNeverStartsPolicy(override: Bool?) {
        let f = Fixture(); f.driver.override = override
        #expect(!f.run(.enable).active)
        #expect(f.driver.targets.isEmpty && f.journal.pending == nil)
    }
}
