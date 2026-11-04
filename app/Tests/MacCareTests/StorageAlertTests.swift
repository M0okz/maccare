import XCTest
@testable import MacCare

final class StorageAlertTests: XCTestCase {
    private func withPolicy(_ body: (StorageAlertPolicy) throws -> Void) rethrows {
        let suite = "MacCare.StorageAlertTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(StorageAlertPolicy(defaults: defaults))
    }

    func testLowSpaceUsesRelativeAndAbsoluteThresholds() {
        XCTAssertTrue(StorageAlertPolicy.isLow(free: 43_170_000_000, total: 500_000_000_000))
        XCTAssertTrue(StorageAlertPolicy.isLow(free: 9_000_000_000, total: 64_000_000_000))
        XCTAssertTrue(StorageAlertPolicy.isLow(free: 50_000_000_000, total: 500_000_000_000))
        XCTAssertFalse(StorageAlertPolicy.isLow(free: 60_000_000_000, total: 500_000_000_000))
        XCTAssertFalse(StorageAlertPolicy.isLow(free: 10_000_000_000, total: 64_000_000_000))
    }

    func testInvalidSamplesCannotTriggerAlerts() {
        XCTAssertFalse(StorageAlertPolicy.isLow(free: 0, total: 0))
        XCTAssertFalse(StorageAlertPolicy.isLow(free: 101, total: 100))
    }

    func testReminderSurvivesControllerRecreationAndExpiresAfterOneDay() {
        withPolicy { policy in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertTrue(policy.shouldPresent(free: 1, total: 100, now: now))
            policy.recordPresentation(at: now)
            let recreated = StorageAlertPolicy(defaults: policy.defaults)
            XCTAssertFalse(recreated.shouldPresent(free: 1, total: 100, now: now.addingTimeInterval(86_399)))
            XCTAssertTrue(recreated.shouldPresent(free: 1, total: 100, now: now.addingTimeInterval(86_400)))
        }
    }

    func testDayAndWeekSnoozesPersistAndExpire() {
        for days in [1, 7] {
            withPolicy { policy in
                let now = Date(timeIntervalSince1970: 1_800_000_000)
                policy.snooze(days: days, from: now)
                let end = Calendar.current.date(byAdding: .day, value: days, to: now)!
                let recreated = StorageAlertPolicy(defaults: policy.defaults)
                XCTAssertFalse(recreated.shouldPresent(free: 1, total: 100, now: end.addingTimeInterval(-1)))
                XCTAssertTrue(recreated.shouldPresent(free: 1, total: 100, now: end))
            }
        }
    }

    func testDisabledAndRecoveredDiskSuppressAlerts() {
        withPolicy { policy in
            XCTAssertFalse(policy.shouldPresent(free: 60_000_000_000, total: 500_000_000_000))
            policy.defaults.set(false, forKey: StorageAlertPolicy.enabledKey)
            XCTAssertFalse(policy.shouldPresent(free: 0, total: 100))
            policy.defaults.set(true, forKey: StorageAlertPolicy.enabledKey)
            XCTAssertTrue(policy.shouldPresent(free: 0, total: 100))
        }
    }
}
