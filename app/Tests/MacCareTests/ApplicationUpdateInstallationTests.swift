import XCTest
import CryptoKit
import Sparkle
@testable import MacCare

final class ApplicationUpdateInstallationTests: XCTestCase {
    private func makeApp(_ root: URL, name: String = "Editor.app", id: String = "org.example.Editor", version: String = "1.0") throws -> URL {
        let app = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":id, "CFBundleShortVersionString":version], format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacCare-Update-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor func testSparkleCompletionDelegatesAreVisibleToTheObjectiveCRuntime() {
        let installer = ApplicationUpdateInstaller()
        XCTAssertTrue(installer.responds(to: #selector(SPUUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))))
        XCTAssertTrue(installer.responds(to: #selector(SPUStandardUserDriverDelegate.standardUserDriverWillFinishUpdateSession)))
    }

    func testOnlyExistingAppsUnderExplicitRootsAndNoSymlinkOrSelfTarget() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeApp(root)
        let policy = ApplicationUpdatePolicy(roots: [root])
        XCTAssertEqual(try policy.target(url: app, expectedVersion: "2.0").bundleID, "org.example.Editor")
        XCTAssertThrowsError(try ApplicationUpdatePolicy().target(url: app, expectedVersion: "2.0"))
        XCTAssertThrowsError(try policy.target(url: app, expectedVersion: "1.0"))
        XCTAssertThrowsError(try policy.target(url: root.appendingPathComponent("Missing.app"), expectedVersion: "2.0"))
        let link = root.appendingPathComponent("Link.app");try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        XCTAssertThrowsError(try policy.target(url: link, expectedVersion: "2.0"))
        let selfApp = try makeApp(root, name: "MacCare.app", id: "org.maccare.app")
        XCTAssertThrowsError(try policy.target(url: selfApp, expectedVersion: "2.0"))
    }

    func testWrongIdentityOldVersionAndTooOldDownloadAreRefused() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at: root) }
        let old = try makeApp(root);let policy = ApplicationUpdatePolicy(roots: [root])
        let target = try policy.target(url: old, expectedVersion: "2.0")
        let wrong = try makeApp(root, name: "Wrong.app", id: "org.other.Editor", version: "2.0")
        let stale = try makeApp(root, name: "Stale.app", version: "1.5")
        let downgrade = try makeApp(root, name: "Downgrade.app", version: "0.9")
        let right = try makeApp(root, name: "Right.app", version: "2.0.0")
        XCTAssertThrowsError(try policy.validateCandidate(at: wrong, target: target))
        XCTAssertThrowsError(try policy.validateCandidate(at: stale, target: target))
        XCTAssertThrowsError(try policy.validateCandidate(at: downgrade, target: target))
        XCTAssertNoThrow(try policy.validateCandidate(at: right, target: target))
        XCTAssertThrowsError(try ApplicationUpdateArchive.teamID(at: right), "Unsigned bundles cannot be installed")
    }

    func testInstalledVersionIsReadAgainAfterAReplacementEvenWhenBundleWasCached() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let app = try makeApp(root)
        let cached = try XCTUnwrap(Bundle(url:app))
        XCTAssertEqual(cached.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,"1.0")
        _ = try makeApp(root,version:"2.0")
        let fresh = InstalledUpdateApplication.read(.init(url:app,name:"Editor",bundleId:"org.example.Editor"))
        XCTAssertEqual(fresh?.version,"2.0")
    }

    func testDownloadChecksumsRejectCorruptionAndInvalidDigest() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("update.zip");let bytes = Data("owned fixture".utf8);try bytes.write(to: file)
        let hash = SHA256.hash(data: bytes).map { String(format:"%02x",$0) }.joined()
        XCTAssertNoThrow(try ApplicationUpdateArchive.checkHash(of: file, expected: hash))
        XCTAssertThrowsError(try ApplicationUpdateArchive.checkHash(of: file, expected: String(repeating:"0", count:64)))
        XCTAssertThrowsError(try ApplicationUpdateArchive.checkHash(of: file, expected: "no_check"))
    }

    func testHomebrewCannotUpdateAnotherCopyOfTheSameApplication() throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let first = try makeApp(root,name:"First.app")
        let second = try makeApp(root,name:"Second.app")
        let version = root.appendingPathComponent("Caskroom/editor/1.0")
        try FileManager.default.createDirectory(at:version,withIntermediateDirectories:true)
        try FileManager.default.createSymbolicLink(at:version.appendingPathComponent("Editor.app"),withDestinationURL:first)
        XCTAssertTrue(ApplicationUpdatePolicy.managedCaskMatches(directory:version.deletingLastPathComponent(),target:first))
        XCTAssertFalse(ApplicationUpdatePolicy.managedCaskMatches(directory:version.deletingLastPathComponent(),target:second))
    }

    func testTokensURLsAndArchiveTraversalCannotBecomeCommandsOrPaths() {
        for token in ["--all", "editor;touch /tmp/pwn", "../editor", "editor\n--force", "", "$(whoami)"] { XCTAssertFalse(ApplicationUpdatePolicy.validToken(token)) }
        XCTAssertTrue(ApplicationUpdatePolicy.validToken("visual-studio-code"))
        for raw in ["http://example.org/app.dmg", "file:///Applications/App.app", "https://user:pass@example.org/app.zip"] { XCTAssertFalse(ApplicationUpdatePolicy.validDownloadURL(URL(string:raw)!)) }
        XCTAssertTrue(ApplicationUpdatePolicy.validDownloadURL(URL(string:"https://example.org/app.dmg")!))
        for paths in [["../outside"], ["/absolute"], ["Editor.app/../../outside"], ["..\\outside"]] { XCTAssertFalse(ApplicationUpdatePolicy.validArchivePaths(paths)) }
        XCTAssertTrue(ApplicationUpdatePolicy.validArchivePaths(["Editor.app/Contents/Info.plist"]))
    }

    func testAppStoreAuthorizationUsesOneIdentifierWithoutExecutingTextInThePath() async throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("MacCare's $(touch injected).app/Contents/Helpers/mas")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath:path.path)
        let command = try ApplicationUpdateCommand.appStoreCommand(executable:path,id:123)
        let output = try await ApplicationUpdateCommand.run("/bin/sh", ["-c", command], workingDirectory:root)
        XCTAssertEqual(output,"update\n--force\n123\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("injected").path))
        XCTAssertTrue(try ApplicationUpdateCommand.appStoreAuthorizationScript(executable:path,id:123).hasSuffix("with administrator privileges"))
        XCTAssertThrowsError(try ApplicationUpdateCommand.appStoreCommand(executable:path,id:0))
        XCTAssertThrowsError(try ApplicationUpdateCommand.appStoreCommand(executable:URL(fileURLWithPath:"/tmp/sh"),id:123))
    }

    func testAppStoreAuthorizationScriptCompilesWithoutExecutingIt() async throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let executable = root.appendingPathComponent("MacCare's $(touch injected).app/Contents/Helpers/mas")
        let script = try ApplicationUpdateCommand.appStoreAuthorizationScript(executable:executable,id:123)
        let compiled = root.appendingPathComponent("authorization.scpt")
        _ = try await ApplicationUpdateCommand.run("/usr/bin/osacompile",["-e",script,"-o",compiled.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath:compiled.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("injected").path))
    }

    func testPrivilegedAppStoreCommandRejectsAnUnsignedToolBeforeExecution() async throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let tool = root.appendingPathComponent("mas")
        let marker = root.appendingPathComponent("must-not-run")
        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to:tool)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:tool.path)
        let script = try ApplicationUpdateCommand.appStorePrivilegedCommand(executable:tool,id:123)
        do { _ = try await ApplicationUpdateCommand.run("/bin/sh",["-c",script]);XCTFail("An unsigned tool must not run") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path))
    }

    func testAppStoreIdentifierIsRetainedForAnIndividualUpdate() throws {
        let item = try XCTUnwrap(AppStoreUpdates.parse(#"{"adamID":123,"name":"Editor","version":"1.0","newVersion":"2.0"}"#).first)
        XCTAssertEqual(item.storeID,123)
    }

    func testCommandReaderDrainsLargeStderrWithoutDeadlocking() async throws {
        let output = try await ApplicationUpdateCommand.run("/bin/sh", ["-c", "i=0; while [ $i -lt 3000 ]; do echo fixture-stderr-line >&2; i=$((i+1)); done; echo done"])
        XCTAssertTrue(output.hasSuffix("done\n"))
        do { _ = try await ApplicationUpdateCommand.run("/bin/sh", ["-c", "echo expected-fixture-failure >&2; exit 7"]);XCTFail("Nonzero exit must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("expected-fixture-failure")) }
    }

    func testSystemArchiveExtractionDoesNotWriteThroughAnEscapingSymlink() async throws {
        let root = try temporary();defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside");let unpacked = root.appendingPathComponent("unpacked");let source = root.appendingPathComponent("source")
        for folder in [outside,unpacked,source] { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
        try FileManager.default.createSymbolicLink(at:source.appendingPathComponent("escape"),withDestinationURL:outside)
        let archive = root.appendingPathComponent("escape.zip")
        _ = try await ApplicationUpdateCommand.run("/usr/bin/zip", ["-y",archive.path,"escape"], workingDirectory:source)
        try FileManager.default.removeItem(at:source.appendingPathComponent("escape"))
        try FileManager.default.createDirectory(at:source.appendingPathComponent("escape"),withIntermediateDirectories:true)
        try Data("must not escape".utf8).write(to:source.appendingPathComponent("escape/victim.txt"))
        _ = try await ApplicationUpdateCommand.run("/usr/bin/zip", ["-r",archive.path,"escape/"], workingDirectory:source)
        let listing = try await ApplicationUpdateCommand.run("/usr/bin/zipinfo", ["-l",archive.path])
        XCTAssertTrue(listing.split(separator:"\n").contains { $0.hasPrefix("l") }, "The adversarial fixture must contain a symlink")
        _ = try? await ApplicationUpdateCommand.run("/usr/bin/tar", ["-xf",archive.path,"-C",unpacked.path,"--no-same-owner"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:outside.appendingPathComponent("victim.txt").path))
    }
    func testRealSignedApplicationReplacementWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["MACCARE_INSTALL_NETWORK_QA"] == "1" else { throw XCTSkip("Opt-in signed archive integration, owned fixture only") }
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let installedApp = root.appendingPathComponent("Installed Fixture.app")
        let oldArchive = root.appendingPathComponent("old.dmg")
        let newArchive = root.appendingPathComponent("new.dmg")
        let oldURL = URL(string:"https://github.com/M0okz/maccare/releases/download/v0.2.19/MacCare-0.2.19-arm64.dmg")!
        let newURL = URL(string:"https://github.com/M0okz/maccare/releases/download/v0.2.20/MacCare-0.2.20-arm64.dmg")!
        try await ApplicationUpdateArchive.download(oldURL,to:oldArchive,progress:{ _ in })
        try ApplicationUpdateArchive.checkHash(of:oldArchive,expected:"6430fda069ac0f16455b2e9d9707762b3b8224670d73c7dbf3818cd7f1fc3a4e")
        try await ApplicationUpdateArchive.download(newURL,to:newArchive,progress:{ _ in })
        let mount = root.appendingPathComponent("old-mount");try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:true)
        _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["attach","-readonly","-nobrowse","-mountpoint",mount.path,oldArchive.path])
        do {
            try FileManager.default.copyItem(at:mount.appendingPathComponent("MacCare.app"),to:installedApp)
        } catch {
            _ = try? await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["detach","-quiet",mount.path]);throw error
        }
        _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["detach","-quiet",mount.path])
        // Only this owned fixture may use the product's identifier; production always protects MacCare itself.
        let policy = ApplicationUpdatePolicy(roots:[root],protectedBundleIDs:[])
        let target = try policy.target(url:installedApp,expectedVersion:"0.2.20")
        let preferences = root.appendingPathComponent("preferences.json");try Data("preserved settings".utf8).write(to:preferences)
        let fetch: ApplicationUpdateArchive.Fetch = { _, destination, _ in try FileManager.default.copyItem(at:newArchive,to:destination) }
        do {
            _ = try await ApplicationUpdateArchive.prepare(artifact:.init(url:newURL,sha256:String(repeating:"0",count:64)),target:target,policy:policy,fetch:fetch)
            XCTFail("Corrupted downloads must not replace the fixture")
        } catch {}
        XCTAssertEqual(try ApplicationUpdateTarget.readVersion(ApplicationUpdateTarget.info(at:installedApp)),"0.2.19")
        let prepared = try await ApplicationUpdateArchive.prepare(artifact:.init(url:newURL,sha256:"3212ff7f96ce2ec4df3174cf12e4a08bbfacf90a4ffad0670bf3eaf3b364bdec"),target:target,policy:policy,fetch:fetch)
        defer { prepared.cleanup() }
        try await ApplicationUpdateArchive.replace(prepared,policy:policy)
        XCTAssertEqual(try ApplicationUpdateTarget.readVersion(ApplicationUpdateTarget.info(at:installedApp)),"0.2.20")
        XCTAssertEqual(try String(contentsOf:preferences),"preserved settings")
        XCTAssertEqual(try ApplicationUpdateArchive.teamID(at:installedApp),"5FAF9ZA2X9")
        print("SIGNED_INSTALL_QA", "owned fixture 0.2.19 → 0.2.20, original preserved on bad checksum, preferences unchanged")
    }

    func testPhotoCraft021To022WhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["MACCARE_PHOTOCRAFT_NETWORK_QA"] == "1" else { throw XCTSkip("Opt-in signed archive integration, owned fixture only") }
        let root = try temporary();defer { try? FileManager.default.removeItem(at:root) }
        let installedApp = root.appendingPathComponent("Installed Fixture.app")
        let oldArchive = root.appendingPathComponent("old.dmg")
        let newArchive = root.appendingPathComponent("new.dmg")
        let oldURL = URL(string:"https://github.com/storytold/photocraft/releases/download/v0.21.0/photocraft-0.21.0-macos-universal.dmg")!
        let newURL = URL(string:"https://github.com/storytold/photocraft/releases/download/v0.22.0/photocraft-0.22.0-macos-universal.dmg")!
        try await ApplicationUpdateArchive.download(oldURL,to:oldArchive,progress:{ _ in })
        try ApplicationUpdateArchive.checkHash(of:oldArchive,expected:"aa43b184ae8a2ae2340b7f2522a996431ffec3597ec76b6d977a44a6cbd7bab1")
        try await ApplicationUpdateArchive.download(newURL,to:newArchive,progress:{ _ in })
        let mount = root.appendingPathComponent("old-mount");try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:true)
        _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["attach","-readonly","-nobrowse","-mountpoint",mount.path,oldArchive.path])
        do {
            try FileManager.default.copyItem(at:mount.appendingPathComponent("PhotoCraft.app"),to:installedApp)
        } catch {
            _ = try? await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["detach","-quiet",mount.path]);throw error
        }
        _ = try await ApplicationUpdateCommand.run("/usr/bin/hdiutil",["detach","-quiet",mount.path])
        let policy = ApplicationUpdatePolicy(roots:[root])
        let target = try policy.target(url:installedApp,expectedVersion:"0.22.0")
        let preferences = root.appendingPathComponent("preferences.json");try Data("preserved settings".utf8).write(to:preferences)
        let fetch: ApplicationUpdateArchive.Fetch = { _, destination, _ in try FileManager.default.copyItem(at:newArchive,to:destination) }
        do {
            _ = try await ApplicationUpdateArchive.prepare(artifact:.init(url:newURL,sha256:String(repeating:"0",count:64)),target:target,policy:policy,fetch:fetch)
            XCTFail("Corrupted downloads must not replace the fixture")
        } catch {}
        XCTAssertEqual(try ApplicationUpdateTarget.readVersion(ApplicationUpdateTarget.info(at:installedApp)),"0.21.0")
        let prepared = try await ApplicationUpdateArchive.prepare(artifact:.init(url:newURL,sha256:"027596dcb13db0c0d749315c052493bf587886e9d081afa57cbc6575a4cde6e9"),target:target,policy:policy,fetch:fetch)
        defer { prepared.cleanup() }
        try await ApplicationUpdateArchive.replace(prepared,policy:policy)
        XCTAssertEqual(try ApplicationUpdateTarget.readVersion(ApplicationUpdateTarget.info(at:installedApp)),"0.22.0")
        XCTAssertEqual(try String(contentsOf:preferences),"preserved settings")
        XCTAssertFalse(try ApplicationUpdateArchive.teamID(at:installedApp).isEmpty)
        print("PHOTOCRAFT_INSTALL_QA", "owned fixture 0.21.0 → 0.22.0, original preserved on bad checksum, preferences unchanged")
    }

}
