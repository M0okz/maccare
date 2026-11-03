import XCTest
@testable import MacCare

final class PermissionsTests: XCTestCase {
    func testIndeterminateDiskProbeDoesNotClaimPermission() {
        XCTAssertEqual(FullDiskAccess.permissionState(for: nil), .unknown)
        XCTAssertEqual(FullDiskAccess.permissionState(for: false), .denied)
        XCTAssertEqual(FullDiskAccess.permissionState(for: true), .granted)
    }

    func testSkippingSetupPersistsWithoutGrantingPermissions() async {
        await MainActor.run {
            let suite = "MacCare-QA-Onboarding-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = PermissionsModel(defaults: defaults)
            XCTAssertTrue(model.needsOnboarding)
            XCTAssertFalse(model.allGranted)
            model.completeFirstRun()
            XCTAssertFalse(model.needsOnboarding)
            XCTAssertFalse(model.allGranted)
            XCTAssertTrue(model.showBanner, "Une autorisation inconnue ne doit pas disparaître du rappel.")
            let reopened = PermissionsModel(defaults: defaults)
            XCTAssertFalse(reopened.needsOnboarding)
            reopened.reopen()
            XCTAssertTrue(PermissionsModel(defaults: defaults).needsOnboarding)
        }
    }
}
