import XCTest
import MacCareMaintenance
@testable import MacCare

/// Partage des rôles entre la session, l’administrateur et l’Accès complet au disque.
final class UninstallProtectionTests: XCTestCase {
    private let files = FileManager.default

    private func fixture() throws -> (AppInfo, URL) {
        guard files.isWritableFile(atPath: "/Applications") else { throw XCTSkip("Dossier Applications non accessible en écriture") }
        let id = "org.example.protection." + UUID().uuidString
        let app = AppInfo(url: URL(fileURLWithPath: "/Applications/MacCareFixture-\(UUID()).app"), name: "Fixture", bundleId: id)
        try files.createDirectory(at: app.url, withIntermediateDirectories: false)
        let cache = files.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(id)
        try Data([1]).write(to: cache, options: .withoutOverwriting)
        addTeardownBlock { [files] in try? files.removeItem(at: app.url); try? files.removeItem(at: cache) }
        return (app, cache)
    }

    private func execute(_ selected: [ScanItem], _ app: AppInfo, _ direct: Bool) throws -> [AuthorizedUninstall.Result] {
        try AuthorizedUninstall(uid: getuid(), bundle: app.url.path, bundleID: app.bundleId, direct: direct,
                                items: selected.map { .init(path: $0.path, device: $0.identity.device, inode: $0.identity.inode) }).execute()
    }

    /// Cas Reeder : un paquet App Store appartient à root, ses conteneurs à la session.
    func testRootOwnedBundleLeavesTheUserDataToTheSession() async throws {
        let (app, cache) = try fixture()
        let items = try Engine.inspectPaths([app.url.path, cache.path])
        var authorized = [[String]]()
        var operations = UninstallFileOperations()
        operations.ownedByUser = { $0.path != app.url.path }
        operations.authorize = { selected, app, direct in
            authorized.append(selected.map(\.path))
            return try self.execute(selected, app, direct)
        }
        let report = try await Remover.uninstall(items, app: app, direct: true, operations: operations)
        XCTAssertEqual(authorized, [[app.url.path]])
        XCTAssertEqual(report.removed, 2, "\(report.failed)")
        XCTAssertFalse(files.fileExists(atPath: cache.path))
        XCTAssertFalse(files.fileExists(atPath: app.url.path))
    }

    /// Root est soumis à la confidentialité de macOS : aucun mot de passe n’est demandé pour rien.
    func testPrivacyDenialIsNotEscalatedAndNamesFullDiskAccess() async throws {
        let (app, cache) = try fixture()
        let items = try Engine.inspectPaths([cache.path])
        var operations = UninstallFileOperations()
        operations.remove = { _, _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                          userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -5000)])
        }
        operations.fullDiskAccess = { .denied }
        operations.authorize = { _, _, _ in XCTFail("Autorisation administrateur inutile"); return [] }
        let report = try await Remover.uninstall(items, app: app, direct: false, operations: operations)
        XCTAssertEqual(report.removed, 0)
        XCTAssertEqual(report.failed.map(\.path), [cache.path])
        XCTAssertTrue(try XCTUnwrap(report.failed.first?.error).contains("Accès complet au disque"))
        XCTAssertTrue(files.fileExists(atPath: cache.path))
    }

    func testUnwritableParentStillRequestsAdministrator() async throws {
        let (app, cache) = try fixture()
        let items = try Engine.inspectPaths([cache.path])
        var operations = UninstallFileOperations()
        operations.remove = { _, _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        operations.parentWritable = { _ in false }
        var authorized = [String]()
        operations.authorize = { selected, app, direct in
            authorized += selected.map(\.path)
            return try self.execute(selected, app, direct)
        }
        let report = try await Remover.uninstall(items, app: app, direct: true, operations: operations)
        XCTAssertEqual(authorized, [cache.path])
        XCTAssertEqual(report.removed, 1, "\(report.failed)")
    }

    func testContainerMessagesAndDenialShapes() {
        let home = URL(fileURLWithPath: "/Users/qa/Library")
        let container = home.appendingPathComponent("Containers/app.reeder")
        XCTAssertTrue(UninstallFileOperations.isAppContainer(container))
        XCTAssertTrue(UninstallFileOperations.isAppContainer(home.appendingPathComponent("Group Containers/TEAM.app.reeder")))
        XCTAssertFalse(UninstallFileOperations.isAppContainer(container.appendingPathComponent("Data")))
        XCTAssertFalse(UninstallFileOperations.isAppContainer(home.appendingPathComponent("Application Scripts/app.reeder")))
        let denied = UninstallFileOperations.protectionMessage(for: container, fullDisk: .denied)
        XCTAssertTrue(denied.hasPrefix("macOS protège les conteneurs"))
        XCTAssertTrue(denied.contains("administrateur ne suffit pas"))
        XCTAssertFalse(UninstallFileOperations.protectionMessage(for: container, fullDisk: .granted).contains("Accordez"))
        XCTAssertTrue(UninstallFileOperations.isAccessDenial(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -5000)])))
        XCTAssertFalse(UninstallFileOperations.isAccessDenial(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
    }

    func testReviewFindsWebKitCachesAndHostPreferences() throws {
        let root = files.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let library = root.appendingPathComponent("Library"), darwin = root.appendingPathComponent("C")
        let byHost = library.appendingPathComponent("Preferences/ByHost")
        try files.createDirectory(at: byHost, withIntermediateDirectories: true)
        let host = "669488C5-DF6B-5FDC-B626-95923993E940"
        for name in ["app.reeder.\(host).plist", "app.reeder.SaveLink.\(host).plist", "app.reederx.\(host).plist"] {
            try Data().write(to: byHost.appendingPathComponent(name))
        }
        let app = AppInfo(url: root.appendingPathComponent("Reeder.app"), name: "Reeder", bundleId: "app.reeder")
        let review = UninstallReview(app: app, others: [], embeddedIDs: ["app.reeder.SaveLink"],
                                     library: library, darwinDirectories: [darwin])
        for process in ["GPU", "Networking", "WebContent"] {
            XCTAssertEqual(review.candidates[darwin.appendingPathComponent("com.apple.WebKit.\(process)+app.reeder").path], .exclusive)
        }
        XCTAssertEqual(review.candidates[byHost.appendingPathComponent("app.reeder.\(host).plist").path], .exclusive)
        XCTAssertEqual(review.candidates[byHost.appendingPathComponent("app.reeder.SaveLink.\(host).plist").path], .exclusive)
        XCTAssertNil(review.candidates[byHost.appendingPathComponent("app.reederx.\(host).plist").path])
        XCTAssertFalse(UninstallReview.isHostPreference("app.reeder.SaveLink.\(host).plist", of: "app.reeder"))
    }

    func testMissingBundleNoLongerClaimsTheApplicationStaysInstalled() {
        let app = AppInfo(url: URL(fileURLWithPath: "/QA/Reeder.app"), name: "Reeder", bundleId: "app.reeder")
        let container = ScanItem(id: "c", path: "/Users/qa/Library/Containers/app.reeder", category: "uninstall", size_bytes: 1,
                                 reason: "QA", autoselect: false, identity: FileIdentity(device: 1, inode: 1), owner: nil)
        let detail = UninstallDetailPresentation(app: app, items: [container], selection: ["c"], directDelete: false)
        XCTAssertEqual(detail.consequence, "Les données cochées seront déplacées vers la corbeille.")
        XCTAssertEqual(detail.selectedContainers.map(\.id), ["c"])
    }
}

/// Désinstallation par l’assistant système, confirmée par Touch ID dans l’app.
final class UninstallHelperRouteTests: XCTestCase {
    func testServiceIgnoresAForgedUserAndRejectsMalformedSelections() throws {
        let request = AuthorizedUninstall(uid: getuid() + 1, bundle: "/Applications/Fixture.app", bundleID: "org.example.x",
                                          direct: false, items: [.init(path: "/Applications/Fixture.app", device: 1, inode: 1)])
        let forged = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let outcome = AuthorizedUninstall.serviceReply(selectionJSON: forged, authenticatedUID: getuid())
        XCTAssertNil(outcome.results)
        XCTAssertThrowsError(try UninstallAuthorization.decode(outcome.reply)) {
            XCTAssertEqual($0.localizedDescription, "La sélection ne correspond pas à la session.")
        }
        XCTAssertNil(AuthorizedUninstall.serviceReply(selectionJSON: "{", authenticatedUID: getuid()).results)
    }

    func testServiceRemovesASelectionForTheAuthenticatedUser() throws {
        let files = FileManager.default
        guard files.isWritableFile(atPath: "/Applications") else { throw XCTSkip("Dossier Applications non accessible en écriture") }
        let app = URL(fileURLWithPath: "/Applications/MacCareFixture-\(UUID()).app")
        try files.createDirectory(at: app, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: app) }
        let item = try XCTUnwrap(Engine.inspectPaths([app.path]).first)
        let request = AuthorizedUninstall(uid: getuid(), bundle: app.path, bundleID: nil, direct: true,
                                          items: [.init(path: app.path, device: item.identity.device, inode: item.identity.inode)])
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let outcome = AuthorizedUninstall.serviceReply(selectionJSON: json, authenticatedUID: getuid())
        let results = try UninstallAuthorization.decode(outcome.reply)
        XCTAssertEqual(results.map(\.path), [app.path])
        XCTAssertNil(results.first?.error)
        XCTAssertFalse(files.fileExists(atPath: app.path))
    }
}
