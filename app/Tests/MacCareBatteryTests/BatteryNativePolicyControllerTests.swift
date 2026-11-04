import Foundation
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
        let hardware: NativeChargePolicyHardware
        let controller: BatteryProtectionController
        let session = UUID()
        init(original: NativeChargePolicyPreferences = .init(featureState: .absent, limit: .absent), driver injected: Driver? = nil) {
            let driver = injected ?? Driver(original), journal = Journal()
            self.driver = driver; self.journal = journal
            // An explicit fixed AC context keeps all tests independent of the host Mac.
            let hardware = NativeChargePolicyHardware(driver: driver, identity: { "fixture-M1" }, onAC: { true })
            self.hardware = hardware
            driver.beforeMutation = { #expect(journal.pending != nil, "The original policy must be durable before any write or release") }
            controller = .init(hardware: hardware, markRecovery: { try journal.save($0) }, clearRecovery: { try journal.clear() })
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

    @Test func capturesAbsentKeysInVersionFourBeforeWritingBelowEighty() throws {
        let f = Fixture()
        let result = f.run(.enable)
        #expect(result.active)
        #expect(result.capabilities?.backend == .nativePolicy)
        #expect(f.driver.targets == [70])
        let record = try #require(f.journal.pending)
        #expect(record.version == 4 && record.isValid)
        #expect(record.nativePolicyPreferences == .init(featureState: .absent, limit: .absent))
        #expect(try JSONDecoder().decode(BatteryRecoveryRecord.self, from: JSONEncoder().encode(record)) == record)
    }
    @Test func persistenceFailurePreventsAllMutations() {
        let f = Fixture(); f.journal.failSave = true
        #expect(!f.run(.enable).active)
        #expect(f.driver.targets.isEmpty && f.driver.clears == 0)
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
        #expect(f.journal.pending != nil && f.driver.preferences == original)
        #expect(f.driver.clears == 1)
        f.driver.registered = 85
        let restored = f.controller.tick(snapshot: .init(percent: 60, onAC: true, temperature: 30), now: 15)
        #expect(!restored.active && !restored.restoring)
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
    @Test func nativeCalibrationTargetsTenWithoutAdapterIsolation() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 80).active)
        try #require(f.run(.calibrate, percent: 80, now: 1).cycle?.phase == .chargingToFull)
        let full = f.run(.heartbeat, percent: 100, now: 2)
        #expect(full.cycle?.phase == .dischargingForCalibration)
        #expect(f.driver.targets.last == 10)
        let low = f.run(.heartbeat, percent: 10, now: 3)
        #expect(low.cycle?.phase == .rechargingToFull)
        #expect(f.driver.targets.last == 100)
    }
    @Test func explicitDischargeUsesPolicyButUnpluggingInterruptsIt() throws {
        let f = Fixture(); try #require(f.run(.enable, percent: 90).active)
        try #require(f.run(.discharge, percent: 90, now: 1).cycle != nil)
        #expect(f.driver.targets.last == 70)
        let interrupted = f.run(.heartbeat, percent: 85, onAC: false, now: 2)
        #expect(!interrupted.active && interrupted.error != nil)
        #expect(f.journal.pending == nil)
    }
    @Test func twoSleepWakeCyclesRestoreEveryTimeAndRestartRegistrationGrace() throws {
        let f = Fixture(); try #require(f.run(.enable).active)
        try f.controller.prepareForSleep()
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
        #expect(f.journal.pending != nil)
        f.driver.automaticallyRegister = false
        f.controller.didWake(now: 200)
        let resumed = f.run(.heartbeat, now: 201)
        #expect(resumed.active && resumed.chargeApplication?.elapsed == 0)
        try f.controller.prepareForSleep()
        #expect(f.driver.preferences == .init(featureState: .absent, limit: .absent))
        #expect(f.driver.clears == 2)
        f.controller.didWake(now: 500)
        #expect(f.run(.heartbeat, now: 501).active)
        _ = f.run(.disable, now: 502)
        #expect(f.driver.clears == 3 && f.journal.pending == nil)
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
