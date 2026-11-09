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

    func testInitialSelectionIncludesApplicationAndAssociatedData() {
        let items = [item("app", path: "/QA/./Example.app"),
                     item("data", path: "/QA/Library/Example.app"),
                     item("helper", path: "/QA/Example.app/Contents/Helpers/Helper.app")]
        XCTAssertEqual(UninstallDetailPresentation.initialSelection(app: app, items: items), ["app", "data", "helper"])
        let detail = UninstallDetailPresentation(app: app, items: items, selection: ["app"], directDelete: false)
        XCTAssertTrue(detail.consequence.contains("Les données associées seront conservées."))
        XCTAssertEqual(UninstallDetailPresentation.initialSelection(app: app, items: Array(items.dropFirst())), ["data", "helper"])
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
