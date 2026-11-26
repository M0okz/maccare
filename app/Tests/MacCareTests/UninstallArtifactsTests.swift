import AppKit
import XCTest
import MacCareMaintenance
@testable import MacCare

final class UninstallArtifactsTests: XCTestCase {
    func testLoginHelperCachesScriptsContainersRecentsAndExternalAgent() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let app = AppInfo(url: root.appendingPathComponent("Barbee.app"), name: "Barbee", bundleId: "com.example.Barbee")
        let helper = "com.example.Barbee.LaunchAtLoginHelper"
        func write(_ plist: [String: Any], to url: URL) throws {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        }
        let login = app.url.appendingPathComponent("Contents/Library/LoginItems/Startup.app/Contents/Info.plist")
        try write(["CFBundleIdentifier": helper, "CFBundlePackageType": "APPL"], to: login)
        let metadata = UninstallArtifacts(app: app)
        XCTAssertEqual(metadata.embeddedIDs, [helper])
        let library = root.appendingPathComponent("User/Library")
        let machine = root.appendingPathComponent("Library")
        let cache = root.appendingPathComponent("C")
        let label = "com.example.BarbeeHelper"
        let agent = machine.appendingPathComponent("LaunchAgents/" + label + ".plist")
        let support = machine.appendingPathComponent("Application Support/Barbee Helper")
        try write(["Label": label, "ProgramArguments": [support.appendingPathComponent("bin/helper").path]], to: agent)
        let other = machine.appendingPathComponent("LaunchAgents/com.example.BarbeeOther.plist")
        try write(["Label": "com.example.BarbeeOther", "Program": support.appendingPathComponent("other").path], to: other)
        let review = UninstallReview(app: app, others: [], groupIDs: ["TEAM.com.example.barbee"], embeddedIDs: metadata.embeddedIDs,
                                     library: library, darwinDirectories: [cache], machineLibrary: machine)
        let paths = ["Containers/" + helper, "Application Scripts/" + helper,
                     "Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/" + helper.lowercased() + ".sfl4"]
        for relative in paths { XCTAssertEqual(review.candidates[library.appendingPathComponent(relative).path]?.preselected, true) }
        XCTAssertEqual(review.candidates[cache.appendingPathComponent(helper).path], .exclusive)
        XCTAssertEqual(review.candidates[agent.path], .machine)
        XCTAssertEqual(review.candidates[support.path], .machine)
        XCTAssertNil(review.candidates[other.path])
        XCTAssertNil(review.candidates[library.appendingPathComponent("Containers/" + helper + "2").path])
        XCTAssertNil(review.candidates[machine.path])
        XCTAssertEqual(review.candidates[library.appendingPathComponent("Application Scripts/TEAM.com.example.barbee").path], .declaredGroup)
    }

    func testGroupAndHelperUsedByAnotherApplicationAreKept() {
        let library = URL(fileURLWithPath: "/QA/Library")
        let app = AppInfo(url: URL(fileURLWithPath: "/QA/Foo.app"), name: "Foo", bundleId: "com.example.foo")
        let other = AppInfo(url: URL(fileURLWithPath: "/QA/Else.app"), name: "Else", bundleId: "com.example.else")
        let helper = "com.example.foo.login", group = "group.example.foo"
        let review = UninstallReview(app: app, others: [other], groupIDs: [group], embeddedIDs: [helper],
                                     otherClaims: [helper: other, group: other], library: library)
        for relative in ["Containers/" + helper, "Group Containers/" + group, "Application Scripts/" + group] {
            XCTAssertEqual(review.candidates[library.appendingPathComponent(relative).path], .shared(other.url.path))
        }
    }

    func testPermissionFailureRequestsOneAuthorizationAndPreservesTheCancellationReason() async throws {
        let files = FileManager.default
        let app = AppInfo(url: URL(fileURLWithPath: "/Applications/MacCareFixture-\(UUID()).app"), name: "Fixture",
                          bundleId: "org.example.fixture." + UUID().uuidString)
        try files.createDirectory(at: app.url, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: app.url) }
        let cache = files.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(try XCTUnwrap(app.bundleId))
        try Data([1]).write(to: cache, options: .withoutOverwriting)
        defer { try? files.removeItem(at: cache) }
        let items = try Engine.inspectPaths([app.url.path, cache.path])
        var operations = UninstallFileOperations()
        operations.ownedByUser = { $0.path != app.url.path }
        operations.remove = { _, _ in XCTFail("Aucun retrait avant le paquet"); throw CocoaError(.fileWriteNoPermission) }
        operations.authorize = { selection, _, _ in
            XCTAssertEqual(selection.map(\.path), [app.url.path], "Seul le paquet d’un autre compte passe par l’administrateur")
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Autorisation annulée."])
        }
        let report = try await Remover.uninstall(items, app: app, direct: false, operations: operations)
        XCTAssertEqual(report.failed.first?.error, "Autorisation annulée.")
        XCTAssertEqual(report.kept.map(\.path), [cache.path])
        XCTAssertTrue(report.refused.isEmpty)
        XCTAssertEqual(report.removed, 0)
        XCTAssertTrue(files.fileExists(atPath: cache.path))
    }

    func testOneAuthorizedBatchRemovesBundleAndItsDataInBothModes() async throws {
        let files = FileManager.default
        for direct in [false, true] {
            let id = "org.example.auth." + UUID().uuidString
            let app = AppInfo(url: URL(fileURLWithPath: "/Applications/MacCareFixture-\(UUID()).app"), name: "Fixture", bundleId: id)
            let cache = files.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(id)
            try files.createDirectory(at: app.url, withIntermediateDirectories: false)
            try Data([42]).write(to: cache, options: .withoutOverwriting)
            let items = try Engine.inspectPaths([app.url.path, cache.path])
            let trash = files.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            defer {
                for url in [cache, app.url] {
                    try? files.removeItem(at: url)
                    try? files.removeItem(at: trash.appendingPathComponent(url.lastPathComponent))
                }
            }
            var calls = 0
            var operations = UninstallFileOperations()
            operations.ownedByUser = { _ in false }
            operations.remove = { _, _ in throw CocoaError(.fileWriteNoPermission) }
            operations.authorize = { selected, app, direct in
                calls += 1
                return try AuthorizedUninstall(uid: getuid(), bundle: app.url.path, bundleID: app.bundleId, direct: direct,
                                               items: selected.map { .init(path: $0.path, device: $0.identity.device, inode: $0.identity.inode) }).execute()
            }
            let report = try await Remover.uninstall(items, app: app, direct: direct, operations: operations)
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(report.removed, 2, "\(report.failed)")
            for url in [cache, app.url] {
                XCTAssertFalse(files.fileExists(atPath: url.path))
                XCTAssertEqual(files.fileExists(atPath: trash.appendingPathComponent(url.lastPathComponent).path), !direct)
            }
        }
    }

    func testWorkerRefusesChangedIdentityAndPreservesAnExistingTrashEntry() throws {
        let fm = FileManager.default
        let name = "MacCareUndo-" + UUID().uuidString + ".app"
        let url = URL(fileURLWithPath: "/Applications/" + name)
        let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let previous = trash.appendingPathComponent(name)
        try Data([7]).write(to: previous, options: .withoutOverwriting)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: previous); try? fm.removeItem(at: url) }
        let item = try XCTUnwrap(Engine.inspectPaths([url.path]).first)
        let request = AuthorizedUninstall(uid: getuid(), bundle: url.path, bundleID: nil, direct: false,
                                          items: [.init(path: url.path, device: item.identity.device, inode: item.identity.inode + 1)])
        XCTAssertNotNil(try request.execute().first?.error)
        XCTAssertTrue(fm.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: previous), Data([7]))
    }

    func testSignedWorkerExecutesTheStagedCommandWhenPackaged() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACCARE_TEST_UNINSTALL_HELPER"] else {
            throw XCTSkip("Ce contrôle utilise l’assistant d’un paquet MacCare DEV signé.")
        }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: "/Applications/MacCareSigned-" + UUID().uuidString + ".app")
        let manifest = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + " 'selection.json")
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: manifest); try? fm.removeItem(at: url) }
        let item = try XCTUnwrap(Engine.inspectPaths([url.path]).first)
        let request = AuthorizedUninstall(uid: getuid(), bundle: url.path, bundleID: nil, direct: true,
                                          items: [.init(path: url.path, device: item.identity.device, inode: item.identity.inode)])
        let bytes = try JSONEncoder().encode(request)
        let command = UninstallAuthorization.stagedCommand(helper: URL(fileURLWithPath: path), manifest: manifest, payload: bytes)
        try Data("{}".utf8).write(to: manifest)
        do {
            _ = try await ApplicationUpdateCommand.run("/bin/sh", ["-c", command])
            XCTFail("Une sélection modifiée a été acceptée.")
        } catch { XCTAssertTrue(fm.fileExists(atPath: url.path)) }
        try bytes.write(to: manifest)
        let output = try await ApplicationUpdateCommand.run("/bin/sh", ["-c", command])
        let results = try JSONDecoder().decode([AuthorizedUninstall.Result].self, from: Data(output.utf8))
        XCTAssertEqual(results.map(\.path), [url.path])
        XCTAssertNil(results[0].error)
        XCTAssertFalse(fm.fileExists(atPath: url.path))
    }

    func testNativeAuthorizationScriptCompiles() {
        var error: NSDictionary?
        XCTAssertEqual(NSAppleScript(source: UninstallAuthorization.authorizationScript)?.compileAndReturnError(&error), true, "\(String(describing: error))")
    }
}
