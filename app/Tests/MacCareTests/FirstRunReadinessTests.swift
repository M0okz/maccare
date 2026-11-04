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
