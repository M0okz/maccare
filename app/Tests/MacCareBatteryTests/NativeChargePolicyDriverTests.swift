import Foundation
import Testing
@testable import MacCareBattery

struct NativeChargePolicyDriverTests {
    private enum Failure: Error { case read, write, sync, notify, clear, query }

    private final class Events { var values: [String] = [] }

    private final class Store: NativeChargePolicyPreferenceStore {
        var values: [NativeChargePolicyPreferenceKey: Any] = [:]
        var reads = 0
        var failRead = false
        var failWrite: NativeChargePolicyPreferenceKey?
        var failSync = false
        var alterRead: ((NativeChargePolicyPreferenceKey, Int) -> Any?)?
        let events: Events
        init(_ events: Events) { self.events = events }
        func value(for key: NativeChargePolicyPreferenceKey) throws -> Any? {
            reads += 1
            if failRead { throw Failure.read }
            if let alterRead { return alterRead(key, reads) }
            return values[key]
        }
        func setValues(_ preferences: NativeChargePolicyPreferences) throws {
            for (key, value) in [(NativeChargePolicyPreferenceKey.featureState, preferences.featureState), (.limit, preferences.limit)] {
                events.values.append("set:\(key.rawValue)")
                if failWrite == key { throw Failure.write }
                switch value {
                case .absent: values.removeValue(forKey: key)
                case .integer(let integer): values[key] = NSNumber(value: integer)
                case .boolean(let flag): values[key] = NSNumber(value: flag)
                }
            }
        }
        func synchronize() throws {
            events.values.append("sync")
            if failSync { throw Failure.sync }
        }
    }

    private final class Client: NativeChargePolicyClient {
        var isAvailable = true
        var override: Bool? = false
        var failNotify = false
        var failClear = false
        var afterNotify: (() -> Void)?
        let events: Events
        init(_ events: Events) { self.events = events }
        func reloadPreferences() throws {
            events.values.append("notify")
            if failNotify { throw Failure.notify }
            afterNotify?()
        }
        func clearRegisteredLimit() throws {
            events.values.append("clear")
            if failClear { throw Failure.clear }
        }
        func calibrationOverride() -> Bool? { override }
    }

    private final class Reader: NativeChargePolicyLimitReader {
        var text = "No battery level limits set\n"
        var fails = false
        var calls = 0
        func output() throws -> String {
            calls += 1
            if fails { throw Failure.query }
            return text
        }
    }

    private struct Fixture {
        let events = Events()
        let store: Store
        let client: Client
        let reader = Reader()
        let driver: SystemNativeChargePolicyDriver
        init() {
            store = Store(events); client = Client(events)
            driver = SystemNativeChargePolicyDriver(store: store, client: client, reader: reader)
        }
    }

    @Test(arguments: [NativeChargePolicyPreferenceValue.absent, .integer(0), .integer(1), .boolean(false), .boolean(true)])
    func preferenceValueRoundTripsWithoutNormalizingItsType(value: NativeChargePolicyPreferenceValue) throws {
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(NativeChargePolicyPreferenceValue.self, from: encoded) == value)
    }

    @Test func snapshotsRequireARepresentableTargetWhenEnabled() throws {
        #expect(NativeChargePolicyPreferences(featureState: .absent, limit: .absent).isValid)
        #expect(NativeChargePolicyPreferences(featureState: .integer(0), limit: .absent).isValid)
        #expect(NativeChargePolicyPreferences(featureState: .boolean(false), limit: .integer(60)).isValid)
        #expect(NativeChargePolicyPreferences(featureState: .integer(1), limit: .integer(1)).isValid)
        #expect(NativeChargePolicyPreferences(featureState: .boolean(true), limit: .integer(100)).isValid)
        for snapshot in [
            NativeChargePolicyPreferences(featureState: .integer(1), limit: .absent),
            .init(featureState: .boolean(true), limit: .absent),
            .init(featureState: .integer(2), limit: .integer(60)),
            .init(featureState: .integer(0), limit: .integer(0)),
            .init(featureState: .integer(0), limit: .integer(101)),
            .init(featureState: .integer(0), limit: .boolean(true))
        ] { #expect(snapshot.isValid == false) }
    }

    @Test func absenceDoesNotProveAvailabilityOrWriteAnything() throws {
        let fixture = Fixture()
        fixture.client.isAvailable = false
        #expect(fixture.driver.isAvailable == false)
        #expect(throws: NativeChargePolicyError.unavailable) { try fixture.driver.readPreferences() }
        #expect(throws: NativeChargePolicyError.unavailable) { try fixture.driver.apply(limit: 60) }
        #expect(throws: NativeChargePolicyError.unavailable) { try fixture.driver.clearRegisteredLimit() }
        #expect(throws: NativeChargePolicyError.unavailable) {
            try fixture.driver.restorePreferences(.init(featureState: .absent, limit: .absent))
        }
        #expect(fixture.store.reads == 0)
        #expect(fixture.events.values.isEmpty)
    }

    @Test func readingAbsentKeysAndBooleanFeatureIsReadOnly() throws {
        let fixture = Fixture()
        #expect(try fixture.driver.readPreferences() == .init(featureState: .absent, limit: .absent))
        fixture.store.values = [.featureState: NSNumber(value: true), .limit: NSNumber(value: 60)]
        #expect(try fixture.driver.readPreferences() == .init(featureState: .boolean(true), limit: .integer(60)))
        fixture.store.values[.featureState] = NSNumber(value: 1)
        #expect(try fixture.driver.readPreferences() == .init(featureState: .integer(1), limit: .integer(60)))
        #expect(fixture.events.values.isEmpty)
        #expect(fixture.reader.calls == 0)
    }

    @Test func malformedPropertyListTypesAreNeverCoercedOrWritten() {
        let fixture = Fixture()
        for raw: Any in [NSNumber(value: 1.0), NSNumber(value: 1.5), "1", NSNull(), [1], ["value": 1], NSNumber(value: UInt64.max)] {
            fixture.store.values = [.featureState: raw, .limit: NSNumber(value: 60)]
            #expect(throws: NativeChargePolicyError.invalidPreferences) { try fixture.driver.apply(limit: 60) }
        }
        fixture.store.values = [.featureState: NSNumber(value: 1), .limit: NSNumber(value: true)]
        #expect(throws: NativeChargePolicyError.invalidPreferences) { try fixture.driver.apply(limit: 60) }
        fixture.store.values = [.featureState: NSNumber(value: 0), .limit: NSNumber(value: 60.5)]
        #expect(throws: NativeChargePolicyError.invalidPreferences) { try fixture.driver.apply(limit: 60) }
        #expect(fixture.events.values.isEmpty)
    }

    @Test func changingPreferencePairIsNotCaptured() {
        let fixture = Fixture()
        fixture.store.alterRead = { key, count in key == .featureState ? NSNumber(value: 1) : NSNumber(value: count < 4 ? 60 : 61) }
        #expect(throws: NativeChargePolicyError.inconsistentPreferences) { try fixture.driver.readPreferences() }
        #expect(fixture.events.values.isEmpty)
    }

    @Test(arguments: [0, 101, -1, Int.max])
    func invalidTargetsDoNotEvenReadPreferences(limit: Int) {
        let fixture = Fixture()
        #expect(throws: NativeChargePolicyError.invalidLimit) { try fixture.driver.apply(limit: limit) }
        #expect(fixture.store.reads == 0)
        #expect(fixture.events.values.isEmpty)
    }

    @Test(arguments: [1, 60, 79, 80, 100])
    func applyingAValidTargetWritesOnlyTheTwoOwnedKeysThenFlushesAndNotifies(limit: Int) throws {
        let fixture = Fixture()
        try fixture.driver.apply(limit: limit)
        #expect(try fixture.driver.readPreferences() == .init(featureState: .integer(1), limit: .integer(limit)))
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue", "sync", "notify"])
        #expect(fixture.reader.calls == 0, "Preference confirmation is separate from asynchronous powerd settlement")
    }

    @Test func failedSecondWriteLeavesAnErrorAndCanRestoreAnInitiallyAbsentPair() throws {
        let fixture = Fixture()
        fixture.store.failWrite = .limit
        #expect(throws: Failure.write) { try fixture.driver.apply(limit: 60) }
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue"])
        #expect(throws: NativeChargePolicyError.invalidPreferences) { try fixture.driver.readPreferences() }
        fixture.store.failWrite = nil
        try fixture.driver.restorePreferences(.init(featureState: .absent, limit: .absent))
        #expect(fixture.store.values.isEmpty)
        #expect(fixture.events.values.suffix(4) == ["set:MCLFeatureState", "set:mclLimitValue", "sync", "notify"])
    }

    @Test func synchronizationFailureNeverNotifiesOrClaimsSuccess() {
        let fixture = Fixture()
        fixture.store.failSync = true
        #expect(throws: Failure.sync) { try fixture.driver.apply(limit: 60) }
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue", "sync"])
    }

    @Test func notificationFailureIsPropagatedAfterTheWrite() {
        let fixture = Fixture()
        fixture.client.failNotify = true
        #expect(throws: Failure.notify) { try fixture.driver.apply(limit: 60) }
        #expect(fixture.store.values[.limit] as? NSNumber == NSNumber(value: 60))
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue", "sync", "notify"])
    }

    @Test func unconfirmedReadbackIsAnError() {
        let fixture = Fixture()
        fixture.client.afterNotify = { fixture.store.values[.limit] = NSNumber(value: 80) }
        #expect(throws: NativeChargePolicyError.verificationFailed) { try fixture.driver.apply(limit: 60) }
    }

    @Test(arguments: [NativeChargePolicyPreferences(featureState: .boolean(false), limit: .absent),
                     .init(featureState: .boolean(true), limit: .integer(85)),
                     .init(featureState: .integer(0), limit: .integer(95)),
                     .init(featureState: .absent, limit: .integer(100))])
    func restorationPreservesExactAbsenceAndFeatureType(original: NativeChargePolicyPreferences) throws {
        let fixture = Fixture()
        try fixture.driver.apply(limit: 60)
        fixture.events.values = []
        try fixture.driver.restorePreferences(original)
        #expect(try fixture.driver.readPreferences() == original)
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue", "sync", "notify"])
    }

    @Test func failedRestoreDoesNotFallBackOrClearTheAgent() {
        let fixture = Fixture()
        fixture.store.failSync = true
        #expect(throws: Failure.sync) { try fixture.driver.restorePreferences(.init(featureState: .integer(0), limit: .integer(100))) }
        #expect(fixture.events.values == ["set:MCLFeatureState", "set:mclLimitValue", "sync"])
        #expect(fixture.reader.calls == 0)
    }

    @Test func invalidRecoverySnapshotCannotWrite() {
        let fixture = Fixture()
        #expect(throws: NativeChargePolicyError.invalidPreferences) {
            try fixture.driver.restorePreferences(.init(featureState: .integer(1), limit: .absent))
        }
        #expect(fixture.events.values.isEmpty)
    }

    @Test(arguments: [true, nil] as [Bool?])
    func appleCalibrationBlocksApplyRestoreAndRelease(calibration: Bool?) {
        let fixture = Fixture()
        fixture.client.override = calibration
        #expect(throws: NativeChargePolicyError.appleOverride) { try fixture.driver.apply(limit: 60) }
        #expect(throws: NativeChargePolicyError.appleOverride) { try fixture.driver.restorePreferences(.init(featureState: .integer(0), limit: .integer(100))) }
        #expect(throws: NativeChargePolicyError.appleOverride) { try fixture.driver.clearRegisteredLimit() }
        #expect(fixture.events.values.isEmpty)
    }

    @Test func calibrationStartingDuringTheWriteDoesNotProduceSuccess() {
        let fixture = Fixture()
        fixture.client.afterNotify = { fixture.client.override = true }
        #expect(throws: NativeChargePolicyError.appleOverride) { try fixture.driver.apply(limit: 60) }
    }

    @Test func releaseIsSeparateAndPropagatesAgentFailure() throws {
        let fixture = Fixture()
        fixture.client.failClear = true
        #expect(throws: Failure.clear) { try fixture.driver.clearRegisteredLimit() }
        #expect(fixture.events.values == ["clear"])
        #expect(fixture.store.reads == 0)
        fixture.client.failClear = false
        try fixture.driver.clearRegisteredLimit()
        #expect(fixture.events.values == ["clear", "clear"])
    }

    @Test func registeredTargetsAndNoLimitHaveDifferentMeaningFromInvalidOutput() throws {
        let fixture = Fixture()
        #expect(try fixture.driver.registeredLimit() == nil)
        fixture.reader.text = "Battery level limits:\n( { chargeSocLimitSoc = 60; chargeSocLimitOwner = 471; }, { chargeSocLimitSoc = 60; })"
        #expect(try fixture.driver.registeredLimit() == 60)
        fixture.reader.text = "Battery level limits:\n()"
        #expect(try fixture.driver.registeredLimit() == nil)
        #expect(fixture.events.values.isEmpty)
    }

    @Test(arguments: ["", "error", "not supported", "Battery level limits: garbage",
                     "Battery level limits: ({ chargeSocLimitSoc = 0; })",
                     "Battery level limits: ({ chargeSocLimitSoc = 101; })",
                     "Battery level limits: ({ chargeSocLimitSoc = 60.5; })",
                     "Battery level limits: ({ chargeSocLimitSoc = true; })",
                     "Battery level limits: ({ chargeSocLimitSoc = 60; }, { chargeSocLimitSoc = 70; })",
                     "Battery level limits: ({ chargeSocLimitSoc = 70; chargeSocLimitSoc = 60; })",
                     "Battery level limits: ({ chargeSocLimitOwner = 1; })",
                     "No battery level limits set\nwarning"])
    func unknownMalformedOrConflictingTargetsAreErrors(output: String) {
        #expect(throws: NativeChargePolicyError.invalidRegisteredLimits) {
            try SystemNativeChargePolicyDriver.registeredLimit(in: output)
        }
    }

    @Test func queryAndPreferenceReadErrorsArePropagatedWithoutMutation() {
        let fixture = Fixture()
        fixture.reader.fails = true
        #expect(throws: Failure.query) { try fixture.driver.registeredLimit() }
        fixture.store.failRead = true
        #expect(throws: Failure.read) { try fixture.driver.apply(limit: 60) }
        #expect(fixture.events.values.isEmpty)
    }

    @Test func oversizedOutputIsNeverTreatedAsAnEmptyRegistration() {
        #expect(throws: NativeChargePolicyError.invalidRegisteredLimits) {
            try SystemNativeChargePolicyDriver.registeredLimit(in: String(repeating: " ", count: 65_537))
        }
    }

    @Test func restoringAnAlreadyExactPairDoesNotRewriteOrNotify() throws {
        let fixture = Fixture(), original = NativeChargePolicyPreferences(featureState: .boolean(false), limit: .absent)
        fixture.store.values = [.featureState: NSNumber(value: false)]
        try fixture.driver.restorePreferences(original)
        try fixture.driver.restorePreferences(original)
        #expect(fixture.events.values.isEmpty)
        #expect(try fixture.driver.readPreferences() == original)
    }

    @Test func restorationReadFailureCannotTurnIntoAnUnconfirmedWrite() {
        let fixture = Fixture()
        fixture.store.failRead = true
        #expect(throws: Failure.read) { try fixture.driver.restorePreferences(.init(featureState: .absent, limit: .absent)) }
        #expect(fixture.events.values.isEmpty)
    }
}
