import XCTest
@testable import MacCare

final class DeviceLowBatteryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private func device(_ level: Int, id: String = "mobile:phone", age: TimeInterval = 0,
                        viaPhone: Bool = false, symbol: String = "iphone") -> TrayBatteryTelemetry.Accessory {
        .init(id: id, name: "Appareil QA", symbol: symbol, percent: level,
              receivedAt: now.addingTimeInterval(-age), viaPhone: viaPhone)
    }
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "DeviceLowBatteryTests.\(UUID())"
        // Use its registered domain name for deterministic, complete cleanup.
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        test(isolated)
    }
    private func enable(_ defaults: UserDefaults) { defaults.set(true, forKey: AdditionalAlertKind.deviceBattery.enabledKey) }

    func testOptInDefaultAndThresholdConfiguration() {
        withDefaults { defaults in
            var policy = DeviceLowBatteryPolicy(defaults: defaults)
            XCTAssertEqual(policy.threshold, 20)
            XCTAssertFalse(AdditionalAlertReminder(.deviceBattery, defaults: defaults).enabled)
            XCTAssertTrue(policy.candidates([device(10)], at: now).isEmpty)
            enable(defaults)
            XCTAssertEqual(policy.candidates([device(20)], at: now).count, 1)
            XCTAssertTrue(policy.candidates([device(21)], at: now).isEmpty)
            defaults.set(30, forKey: DeviceLowBatteryPolicy.thresholdKey)
            XCTAssertEqual(policy.candidates([device(25)], at: now).count, 1)
            for invalid in [-1, 0, 21, 100] {
                defaults.set(invalid, forKey: DeviceLowBatteryPolicy.thresholdKey)
                XCTAssertEqual(policy.threshold, 20)
            }
        }
    }

    func testOnlyFreshDirectLevelsAreEligible() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            let readings = [device(10, id: "mobile:fresh", age: 180),
                            device(10, id: "mobile:old", age: 181), device(10, id: "mobile:future", age: -1),
                            device(10, id: "mobile:watch", viaPhone: true, symbol: "applewatch"),
                            device(10, id: "hid:unknown"), device(-1), device(101)]
            XCTAssertEqual(policy.candidates(readings, at: now).map(\.id), ["mobile:fresh"])
            var undated = device(10); undated.receivedAt = nil
            XCTAssertTrue(policy.candidates([undated], at: now).isEmpty)
        }
    }

    func testOneAlertPerEpisodeIncludingAcrossRelaunchAndMissingTelemetry() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            let low = device(15)
            XCTAssertEqual(policy.candidates([low], at: now).count, 1)
            policy.record(low, at: now)
            XCTAssertTrue(policy.candidates([device(10)], at: now).isEmpty)
            XCTAssertTrue(policy.candidates([], at: now).isEmpty)
            var relaunched = DeviceLowBatteryPolicy(defaults: defaults)
            XCTAssertTrue(relaunched.candidates([low], at: now).isEmpty)
            defaults.set(false, forKey: AdditionalAlertKind.deviceBattery.enabledKey)
            _ = relaunched.candidates([device(90)], at: now)
            enable(defaults)
            XCTAssertTrue(relaunched.candidates([low], at: now).isEmpty)
        }
    }

    func testHysteresisRequiresFreshRecoveryFivePointsAboveThreshold() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            policy.record(device(15), at: now)
            _ = policy.candidates([device(24)], at: now)
            XCTAssertTrue(policy.candidates([device(20)], at: now).isEmpty)
            _ = policy.candidates([device(90, age: 181)], at: now)
            XCTAssertTrue(policy.candidates([device(20)], at: now).isEmpty)
            _ = policy.candidates([device(25)], at: now)
            XCTAssertEqual(policy.candidates([device(20)], at: now).count, 1)
            var relaunched = DeviceLowBatteryPolicy(defaults: defaults)
            XCTAssertEqual(relaunched.candidates([device(20)], at: now).count, 1)
        }
    }

    func testDevicesAreIndependentSortedAndDuplicateReadingsStaySingle() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            let first = device(15), second = device(5, id: "mobile:ipad", symbol: "ipad")
            XCTAssertEqual(policy.candidates([first, first, second], at: now).map(\.id), [second.id, first.id])
            policy.record(second, at: now)
            XCTAssertEqual(policy.candidates([first, second], at: now).map(\.id), [first.id])
        }
    }

    func testUnpresentedAndStaleCandidatesAreNotConsumed() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            _ = policy.candidates([device(15)], at: now)
            XCTAssertEqual(policy.candidates([device(15)], at: now).count, 1)
            policy.record(device(15, age: 181), at: now)
            XCTAssertEqual(policy.candidates([device(15)], at: now).count, 1)
        }
    }

    func testThresholdChangeDoesNotRepeatAnAlreadyAnnouncedEpisode() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            policy.record(device(15), at: now)
            defaults.set(30, forKey: DeviceLowBatteryPolicy.thresholdKey)
            XCTAssertTrue(policy.candidates([device(25)], at: now).isEmpty)
            _ = policy.candidates([device(35)], at: now)
            XCTAssertEqual(policy.candidates([device(25)], at: now).count, 1)
        }
    }

    func testSnoozePreventsOtherEventsWithoutConsumingTheirEpisodes() {
        withDefaults { defaults in
            enable(defaults)
            let reminder = AdditionalAlertReminder(.deviceBattery, defaults: defaults)
            reminder.record(at: now)
            XCTAssertTrue(reminder.shouldPresent(at: now), "The episode ledger, not a global daily limit, deduplicates devices")
            reminder.snooze(days: 1, from: now)
            XCTAssertFalse(reminder.shouldPresent(at: now.addingTimeInterval(60)))
            XCTAssertTrue(reminder.shouldPresent(at: now.addingTimeInterval(90_000)))
        }
    }

    func testMalformedLedgerDoesNotCrashOrInventRecovery() {
        withDefaults { defaults in
            enable(defaults)
            defaults.set(Data("invalid".utf8), forKey: "additionalAlert.deviceBattery.episodes.v1")
            var policy = DeviceLowBatteryPolicy(defaults: defaults)
            XCTAssertEqual(policy.candidates([device(10)], at: now).count, 1)
        }
    }

    func testWatchReceptionTimeAloneNeverClaimsFreshMeasurement() {
        withDefaults { defaults in
            enable(defaults); var policy = DeviceLowBatteryPolicy(defaults: defaults)
            XCTAssertTrue(policy.candidates([device(1, viaPhone: true, symbol: "applewatch")], at: now).isEmpty)
            policy.record(device(1, viaPhone: true, symbol: "applewatch"), at: now)
            XCTAssertEqual(policy.candidates([device(1)], at: now).count, 1)
        }
    }
}
