import XCTest
@testable import MacCare

final class UninstallDetailTests: XCTestCase {
    private let app = AppInfo(url: URL(fileURLWithPath: "/QA/Example.app", isDirectory: true),
                              name: "Example", bundleId: "org.example.qa")

    private func item(_ id: String, path: String) -> ScanItem {
        ScanItem(id: id, path: path, category: "uninstall", size_bytes: 100,
                 reason: "QA", autoselect: false,
                 identity: FileIdentity(device: 1, inode: 1), owner: nil)
    }

    func testOnlyTheBundleAndIdentifiedLowRiskDataStartSelected() {
        let library = URL(fileURLWithPath: "/QA/Library")
        let review = UninstallReview(app: app, others: [], groupIDs: ["group.example"], library: library)
        XCTAssertEqual(review.use(of: item("app", path: "/QA/./Example.app")), .application)
        XCTAssertEqual(review.candidates["/QA/Library/Preferences/org.example.qa.plist"], .exclusive)
        XCTAssertEqual(review.candidates["/QA/Library/Application Support/org.example.qa"], .personal)
        XCTAssertEqual(review.candidates["/QA/Library/Application Support/Example"], .nameOnly)
        XCTAssertEqual(review.candidates["/QA/Library/Group Containers/group.example"], .group)
        XCTAssertTrue(UninstallDataUse.exclusive.preselected)
        XCTAssertTrue(UninstallDataUse.personal.canRemove)
        XCTAssertFalse(UninstallDataUse.personal.preselected)
        XCTAssertFalse(UninstallDataUse.nameOnly.preselected)
        XCTAssertFalse(UninstallDataUse.group.canRemove)
        XCTAssertNil(review.use(of: item("other", path: "/QA/other.app")))
    }

    func testDuplicateNamesAndBrowserEditionsProtectSharedPaths() {
        let library = URL(fileURLWithPath: "/QA/Library")
        let other = AppInfo(url: URL(fileURLWithPath: "/Elsewhere/Example.app"), name: app.name, bundleId: "org.other")
        let review = UninstallReview(app: app, others: [other], library: library)
        XCTAssertEqual(review.candidates["/QA/Library/Caches/Example"], .shared(other.url.path))
        XCTAssertEqual(review.candidates["/QA/Library/Preferences/org.example.qa.plist"], .exclusive)

        let firefox = AppInfo(url: URL(fileURLWithPath: "/QA/Firefox.app"), name: "Firefox", bundleId: "org.mozilla.firefox")
        let nightly = AppInfo(url: URL(fileURLWithPath: "/QA/Firefox Nightly.app"), name: "Firefox Nightly", bundleId: "org.mozilla.nightly")
        let key = "/QA/Library/Application Support/Firefox"
        XCTAssertEqual(UninstallReview(app: firefox, others: [], library: library).candidates[key], .personal)
        XCTAssertEqual(UninstallReview(app: firefox, others: [nightly], library: library).candidates[key], .shared(nightly.url.path))
    }

    func testOnlyExactBundlePathIsClassifiedAsApplication() {
        let bundle = item("app", path: "/QA/./Example.app")
        let data = item("data", path: "/QA/Library/Example.app")
        let helper = item("helper", path: "/QA/Example.app/Contents/Helpers/Helper.app")
        let detail = UninstallDetailPresentation(app: app, items: [data, bundle, helper],
                                                 selection: ["app", "data"], directDelete: false)
        XCTAssertEqual(detail.applicationItems.map(\.id), ["app"])
        XCTAssertEqual(detail.associatedItems.map(\.id), ["data", "helper"])
        XCTAssertTrue(detail.includesApplication)
        XCTAssertEqual(detail.actionTitle, "Désinstaller Example")
    }

    func testDataOnlySelectionKeepsApplicationInstalled() {
        let detail = UninstallDetailPresentation(app: app,
            items: [item("app", path: "/QA/Example.app"), item("data", path: "/QA/Library/preferences.plist")],
            selection: ["data"], directDelete: false)
        XCTAssertFalse(detail.includesApplication)
        XCTAssertEqual(detail.actionTitle, "Mettre les données à la corbeille")
        XCTAssertTrue(detail.consequence.contains("L’application reste installée."))
    }

    func testPermanentModeIsExplicitForBothSelectionTypes() {
        let bundle = item("app", path: "/QA/Example.app")
        let data = item("data", path: "/QA/Library/preferences.plist")
        for selection: Set<String> in [["app", "data"], ["data"]] {
            let detail = UninstallDetailPresentation(app: app, items: [bundle, data],
                                                     selection: selection, directDelete: true)
            XCTAssertTrue(detail.actionTitle.contains("définitivement"))
            XCTAssertTrue(detail.consequence.contains("supprimées définitivement"))
            XCTAssertFalse(detail.consequence.contains("corbeille"))
        }
    }

    func testMissingBundleAndEmptySelectionNeverClaimUninstall() {
        let data = item("data", path: "/QA/Library/preferences.plist")
        let detail = UninstallDetailPresentation(app: app, items: [data], selection: [], directDelete: false)
        XCTAssertTrue(detail.applicationItems.isEmpty)
        XCTAssertFalse(detail.includesApplication)
        XCTAssertFalse(detail.hasSelection)
        XCTAssertFalse(detail.actionTitle.contains("Désinstaller"))
        XCTAssertEqual(detail.consequence, "Sélectionnez les éléments à retirer.")
    }
}
