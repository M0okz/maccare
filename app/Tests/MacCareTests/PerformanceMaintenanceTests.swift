import XCTest
import CSQLite
import MacCareMaintenance
@testable import MacCare

final class PerformanceMaintenanceTests: XCTestCase {
    func testHelperPlansAreClosedAndUseAuthenticatedUserOnly() {
        for task in PerformanceTask.allCases {
            XCTAssertNil(PrivilegedMaintenance.commands(for: task, authenticatedUID: 0))
        }
        XCTAssertNil(PrivilegedMaintenance.commands(for: .mail, authenticatedUID: 501))
        XCTAssertEqual(PrivilegedMaintenance.commands(for: .purgeable, authenticatedUID: 501), [LocalSnapshotMaintenance.thinningCommand])
        let permissions = PrivilegedMaintenance.commands(for: .permissions, authenticatedUID: 502)!
        XCTAssertEqual(permissions, [.init("/usr/sbin/diskutil", ["resetUserPermissions", "/", "502"], timeout: 600)])
        let spotlight = PrivilegedMaintenance.commands(for: .spotlight, authenticatedUID: 501)!
        XCTAssertEqual(spotlight, [.init("/usr/bin/mdutil", ["-E", "/"], timeout: 120)])
        let dns = PrivilegedMaintenance.commands(for: .dns, authenticatedUID: 501)!
        XCTAssertEqual(dns.map(\.executable), ["/usr/bin/dscacheutil", "/usr/bin/killall"])
        XCTAssertEqual(dns.map(\.arguments), [["-flushcache"], ["-HUP", "mDNSResponder"]])
    }

    func testDisabledSpotlightIsNeverEnabledOrErased() {
        var calls: [MaintenanceCommand] = []
        let report = PrivilegedMaintenance.execute(.spotlight, authenticatedUID: 501) { command in
            calls.append(command)
            return .init(status: 0, text: "/:\n Indexing disabled.\n")
        }
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(calls.map(\.arguments), [["-s", "/"]])
    }

    func testSpotlightSuccessMeansStartedNotCompletedIndexing() {
        var count = 0
        let report = PrivilegedMaintenance.execute(.spotlight, authenticatedUID: 501) { _ in
            count += 1
            return .init(status: 0, text: "Indexing enabled.")
        }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(report.status, .started)
    }

    func testDNSFailureAfterFirstCommandIsPartial() {
        var count = 0
        let report = PrivilegedMaintenance.execute(.dns, authenticatedUID: 501) { _ in
            count += 1
            return .init(status: count == 1 ? 0 : 1, text: "fixture")
        }
        XCTAssertEqual(report.status, .partial)
        XCTAssertFalse(report.succeeded)
    }

    func testPrivilegeTimeoutIsNotReportedAsSuccess() {
        let report = PrivilegedMaintenance.execute(.permissions, authenticatedUID: 501) { _ in
            .init(status: 0, timedOut: true)
        }
        XCTAssertEqual(report.status, .failed)
    }

    func testRunnerDrainsLargeOutputAndTimesOut() {
        let output = MaintenanceCommandRunner.run(.init("/usr/bin/printf", ["%070000d", "1"]))
        XCTAssertTrue(output.ok)
        XCTAssertEqual(output.text.utf8.count, 65536)
        let timed = MaintenanceCommandRunner.run(.init("/bin/sleep", ["5"], timeout: 0.05))
        XCTAssertTrue(timed.timedOut)
        XCTAssertFalse(timed.ok)
    }

    func testMailVacuumPreservesMessagesAttachmentsAndIntegrity() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let index = home.appendingPathComponent("Library/Mail/V99/MailData/Envelope Index")
        try sql(index, "CREATE TABLE messages (id INTEGER PRIMARY KEY, subject TEXT); INSERT INTO messages VALUES (1, 'fixture message'); CREATE TABLE attachments (message_id INTEGER, data BLOB); INSERT INTO attachments VALUES(1, X'010203');")
        let report = MailIndexMaintenance.compact(home: home, isMailRunning: { false })
        XCTAssertEqual(report.status, .completed, report.message)
        XCTAssertEqual(try value(index, "SELECT subject FROM messages WHERE id=1"), "fixture message")
        XCTAssertEqual(try value(index, "SELECT hex(data) FROM attachments"), "010203")
        XCTAssertEqual(try value(index, "PRAGMA integrity_check"), "ok")
    }

    func testMailRunningDoesNotModifyDatabase() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let index = home.appendingPathComponent("Library/Mail/V99/MailData/Envelope Index")
        try sql(index, "CREATE TABLE messages (id INTEGER);")
        let before = try Data(contentsOf: index)
        XCTAssertEqual(MailIndexMaintenance.compact(home: home, isMailRunning: { true }).status, .failed)
        XCTAssertEqual(try Data(contentsOf: index), before)
    }

    func testMailRejectsSymlinkAndDoesNotCreateMissingIndex() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let index = home.appendingPathComponent("Library/Mail/V99/MailData/Envelope Index")
        XCTAssertThrowsError(try MailIndexMaintenance.locate(home: home))
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
        let target = home.appendingPathComponent("canary.sqlite")
        try sql(target, "CREATE TABLE messages (id INTEGER);")
        let before = try Data(contentsOf: target)
        try FileManager.default.createSymbolicLink(at: index, withDestinationURL: target)
        XCTAssertEqual(MailIndexMaintenance.compact(home: home, isMailRunning: { false }).status, .failed)
        XCTAssertEqual(try Data(contentsOf: target), before)
    }

    func testUnsupportedMailSchemaIsNotRewritten() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let index = home.appendingPathComponent("Library/Mail/V99/MailData/Envelope Index")
        try sql(index, "CREATE TABLE unrelated (value TEXT); INSERT INTO unrelated VALUES ('canary');")
        let before = try Data(contentsOf: index)
        XCTAssertEqual(MailIndexMaintenance.compact(home: home, isMailRunning: { false }).status, .failed)
        XCTAssertEqual(try Data(contentsOf: index), before)
    }

    func testMailRefusesImplicitMessageRowIDsBeforeVacuum() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let index = home.appendingPathComponent("Library/Mail/V99/MailData/Envelope Index")
        try sql(index, "CREATE TABLE messages (subject TEXT); INSERT INTO messages (rowid, subject) VALUES (99, 'preserve rowid');")
        let before = try Data(contentsOf: index)
        XCTAssertEqual(MailIndexMaintenance.compact(home: home, isMailRunning: { false }).status, .failed)
        XCTAssertEqual(try Data(contentsOf: index), before)
        XCTAssertEqual(try value(index, "SELECT rowid FROM messages"), "99")
    }

    func testPurgePlanCannotExtendToNewItemsAndExpiredPlanRefuses() {
        let plan = PurgeableCachePlan(items: [], rule: "", root: "/nonexistent", createdAt: Date().addingTimeInterval(-901))
        XCTAssertEqual(PurgeableCacheService.execute(plan, allowedIDs: []).status, .failed)
    }

    func testCachePurgeDeletesOnlyApprovedFixtureAndPreservesExternalCanary() throws {
        let name = "org.maccare.fixture." + UUID().uuidString
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let cache = root.appendingPathComponent(name)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("maccare-canary-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("external canary".utf8).write(to: external)
        defer {
            try? FileManager.default.removeItem(at: cache)
            try? FileManager.default.removeItem(at: external)
        }
        try Data(repeating: 1, count: 4096).write(to: cache.appendingPathComponent("generated-cache"))
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("external-link"), withDestinationURL: external)
        let plan = try PurgeableCacheService.prepare(allowedIDs: [name], exclusions: [])
        XCTAssertEqual(plan.items.map { URL(fileURLWithPath: $0.path).lastPathComponent }, [name])
        let report = PurgeableCacheService.execute(plan, allowedIDs: [name])
        XCTAssertTrue(report.succeeded, report.message + report.details)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(try Data(contentsOf: external), Data("external canary".utf8))
    }

    func testCachePurgeRechecksClosedAppsBeforeDeleting() throws {
        let name = "org.maccare.fixture." + UUID().uuidString
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/" + name)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        try Data("keep".utf8).write(to: cache.appendingPathComponent("cache"))
        let plan = try PurgeableCacheService.prepare(allowedIDs: [name], exclusions: [])
        XCTAssertFalse(plan.items.isEmpty)
        let report = PurgeableCacheService.execute(plan, allowedIDs: [])
        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("cache")), "keep")
    }

    private func fixture() throws -> URL {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("maccare-mail-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mail/V99/MailData"), withIntermediateDirectories: true)
        return home
    }

    private func sql(_ url: URL, _ statement: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw NSError(domain: "SQLite fixture", code: 1) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "SQLite fixture", code: 2) }
    }

    private func value(_ url: URL, _ query: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { throw NSError(domain: "SQLite fixture", code: 3) }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw NSError(domain: "SQLite fixture", code: 4) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw NSError(domain: "SQLite fixture", code: 5) }
        return String(cString: bytes)
    }
}
