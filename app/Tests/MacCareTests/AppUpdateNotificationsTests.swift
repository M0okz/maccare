import XCTest
import UserNotifications
import Combine
@testable import MacCare

@MainActor
final class AppUpdateNotificationsTests: XCTestCase {
    private func preferences() -> (String, UserDefaults) {
        let name = "MacCare-update-notification-test-" + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }

    func testOneBannerPerBuildPersistsAcrossServiceInstances() async {
        let (name, defaults) = preferences(); defer { defaults.removePersistentDomain(forName: name) }
        var requests: [UNNotificationRequest] = []
        let service = AppUpdateNotifications(defaults: defaults, authorization: { .authorized }, deliver: { requests.append($0) }, remove: {})
        let first = await service.announce(version: "0.2.25", build: "27")
        let duplicate = await service.announce(version: "0.2.25", build: "27")
        let relaunched = AppUpdateNotifications(defaults: defaults, authorization: { .authorized }, deliver: { requests.append($0) }, remove: {})
        let repeatedAfterLaunch = await relaunched.announce(version: "0.2.25", build: "27")
        let next = await relaunched.announce(version: "0.2.26", build: "28")
        XCTAssertTrue(first); XCTAssertFalse(duplicate); XCTAssertFalse(repeatedAfterLaunch); XCTAssertTrue(next)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.identifier, AppUpdateNotifications.identifier)
        XCTAssertTrue(requests.first?.content.body.contains("0.2.25") == true)
        XCTAssertNil(requests.first?.content.sound)
        XCTAssertNil(requests.first?.trigger)
    }

    func testNoPermissionOrDisabledPreferenceDoesNotConsumeTheReminder() async {
        let (name, defaults) = preferences(); defer { defaults.removePersistentDomain(forName: name) }
        var status: UNAuthorizationStatus = .notDetermined
        var delivered = 0
        let service = AppUpdateNotifications(defaults: defaults, authorization: { status }, deliver: { _ in delivered += 1 }, remove: {})
        let unknown = await service.announce(version: "0.2.25", build: "27")
        status = .denied
        let denied = await service.announce(version: "0.2.25", build: "27")
        status = .authorized; defaults.set(false, forKey: AppUpdateNotifications.enabledKey)
        let disabled = await service.announce(version: "0.2.25", build: "27")
        XCTAssertFalse(unknown); XCTAssertFalse(denied); XCTAssertFalse(disabled)
        XCTAssertNil(defaults.string(forKey: AppUpdateNotifications.lastBuildKey)); XCTAssertEqual(delivered, 0)
        defaults.set(true, forKey: AppUpdateNotifications.enabledKey)
        let enabled = await service.announce(version: "0.2.25", build: "27")
        XCTAssertTrue(enabled); XCTAssertEqual(delivered, 1)
    }

    func testFailedDeliveryCanBeRetried() async {
        let (name, defaults) = preferences(); defer { defaults.removePersistentDomain(forName: name) }
        var attempts = 0
        let service = AppUpdateNotifications(defaults: defaults, authorization: { .authorized }, deliver: { _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "OwnedNotificationFixture", code: 1) }
        }, remove: {})
        let failed = await service.announce(version: "0.2.25", build: "27")
        XCTAssertFalse(failed); XCTAssertNil(defaults.string(forKey: AppUpdateNotifications.lastBuildKey))
        let retry = await service.announce(version: "0.2.25", build: "27")
        XCTAssertTrue(retry); XCTAssertEqual(attempts, 2)
    }

    func testClearingDuringPermissionLookupPreventsALateBanner() async {
        let (name, defaults) = preferences(); defer { defaults.removePersistentDomain(forName: name) }
        let entered = expectation(description: "Permission lookup entered")
        var continuation: CheckedContinuation<UNAuthorizationStatus, Never>?
        var delivered = 0
        let service = AppUpdateNotifications(defaults: defaults, authorization: {
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
        }, deliver: { _ in delivered += 1 }, remove: {})
        let task = Task { await service.announce(version: "0.2.25", build: "27") }
        await fulfillment(of: [entered], timeout: 2)
        service.clear()
        continuation?.resume(returning: .authorized)
        let result = await task.value
        XCTAssertFalse(result); XCTAssertEqual(delivered, 0)
    }

    func testClearingDuringDeliveryRemovesALateAcceptedRequest() async {
        let (name, defaults) = preferences(); defer { defaults.removePersistentDomain(forName: name) }
        let entered = expectation(description: "Delivery entered")
        var continuation: CheckedContinuation<Void, Never>?
        var bannerPresent = false
        let service = AppUpdateNotifications(defaults: defaults, authorization: { .authorized }, deliver: { _ in
            await withCheckedContinuation { continuation = $0; entered.fulfill() }
            bannerPresent = true
        }, remove: { bannerPresent = false })
        let task = Task { await service.announce(version: "0.2.25", build: "27") }
        await fulfillment(of: [entered], timeout: 2)
        service.clear()
        let overlapping = await service.announce(version: "0.2.26", build: "28")
        XCTAssertFalse(overlapping, "A new delivery must wait for the cancelled request to finish")
        continuation?.resume()
        let result = await task.value
        XCTAssertFalse(result); XCTAssertFalse(bannerPresent)
        XCTAssertNil(defaults.string(forKey: AppUpdateNotifications.lastBuildKey))
    }

    func testUpdateNotificationRoutesToUpdaterAndOtherNotificationsKeepTheirRoute() {
        let router = NotificationRouter()
        var scans = 0; var updates = 0
        router.onOpen = { scans += 1 }
        let observation = NotificationCenter.default.publisher(for: .appUpdateNotificationSelected).sink { _ in updates += 1 }
        defer { observation.cancel() }
        router.openNotification(identifier: AppUpdateNotifications.identifier)
        XCTAssertEqual(updates, 1); XCTAssertEqual(scans, 0)
        router.openNotification(identifier: "maccare.scheduled-scan")
        XCTAssertEqual(updates, 1); XCTAssertEqual(scans, 1)
    }
}
