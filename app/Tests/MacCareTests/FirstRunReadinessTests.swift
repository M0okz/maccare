import XCTest
@testable import MacCare

final class FirstRunReadinessTests: XCTestCase {
    func testInstalledLocationsAreNotTemporary() {
        XCTAssertFalse(AppInstallLocation.isTemporary(path: "/Applications/MacCare.app", onReadOnlyVolume: false))
        XCTAssertFalse(AppInstallLocation.isTemporary(path: "/Users/a/Applications/MacCare.app", onReadOnlyVolume: false))
    }

    func testDiskImageAndTranslocatedCopiesAreTemporary() {
        XCTAssertTrue(AppInstallLocation.isTemporary(path: "/Volumes/MacCare/MacCare.app", onReadOnlyVolume: true))
        XCTAssertTrue(AppInstallLocation.isTemporary(
            path: "/private/var/folders/ab/T/AppTranslocation/1234/d/MacCare.app", onReadOnlyVolume: false))
    }

    func testOnlyALoginLaunchWithAReachableAppStartsWithoutWindow() {
        XCTAssertTrue(LoginLaunch.startsWithoutWindow(launchedAtLogin: true, menuBarEnabled: true, firstRunCompleted: true))
        XCTAssertFalse(LoginLaunch.startsWithoutWindow(launchedAtLogin: false, menuBarEnabled: true, firstRunCompleted: true))
        XCTAssertFalse(LoginLaunch.startsWithoutWindow(launchedAtLogin: true, menuBarEnabled: false, firstRunCompleted: true))
        XCTAssertFalse(LoginLaunch.startsWithoutWindow(launchedAtLogin: true, menuBarEnabled: true, firstRunCompleted: false))
    }

    func testLoginLaunchNeedsTheEnabledItemAndAnEventOrARecentSession() {
        XCTAssertTrue(LoginLaunch.launchedAtLogin(itemEnabled: true, launchEvent: true, sessionAge: 9000))
        XCTAssertTrue(LoginLaunch.launchedAtLogin(itemEnabled: true, launchEvent: false, sessionAge: 20))
        XCTAssertFalse(LoginLaunch.launchedAtLogin(itemEnabled: true, launchEvent: false, sessionAge: 600))
        XCTAssertFalse(LoginLaunch.launchedAtLogin(itemEnabled: true, launchEvent: false, sessionAge: nil))
        XCTAssertFalse(LoginLaunch.launchedAtLogin(itemEnabled: false, launchEvent: true, sessionAge: 20))
    }

    func testInfoPlistExplainsEveryFolderPrompt() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        for key in ["NSAppleEventsUsageDescription", "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
                    "NSDownloadsFolderUsageDescription", "NSRemovableVolumesUsageDescription", "NSNetworkVolumesUsageDescription"] {
            XCTAssertFalse((info[key] as? String ?? "").isEmpty, key)
        }
    }
}
