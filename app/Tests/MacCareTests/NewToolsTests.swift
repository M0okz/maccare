import XCTest
import CSQLite
@testable import MacCare

final class NewToolsTests: XCTestCase {
    func testPermissionDatabaseIsReadOnlyAndKeepsTargetsAndManagedPolicies() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("TCC.db").path
        try database(path, sql: """
            CREATE TABLE access(service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER, indirect_object_identifier TEXT, auth_reason INTEGER);
            INSERT INTO access VALUES('kTCCServiceCamera','org.example.demo',0,2,'UNUSED',2);
            INSERT INTO access VALUES('kTCCServiceAppleEvents','org.example.demo',0,2,'org.example.target',2);
            INSERT INTO access VALUES('kTCCServiceMicrophone','org.example.managed',0,2,'UNUSED',6);
            INSERT INTO access VALUES('kTCCServicePhotos','org.example.denied',0,0,'UNUSED',2);
            """)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let result = try ApplicationPermissionStore.read(path: path, system: false)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result[0].canReset)
        XCTAssertEqual(result[1].target, "org.example.target")
        XCTAssertFalse(result[1].canReset, "L’automatisation doit être gérée par macOS, pas réinitialisée plus largement que la cible affichée")
        XCTAssertFalse(result[2].canReset)
        XCTAssertTrue(result[2].managed)
        XCTAssertFalse(result[3].granted)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), before)
        XCTAssertTrue(try ApplicationPermissionStore.read(path: path, system: true).allSatisfy { !$0.canReset })
    }

    func testLegacyPermissionSchemaAndUnknownSchema() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old.db").path
        try database(old, sql: "CREATE TABLE access(service TEXT,client TEXT,client_type INTEGER,allowed INTEGER); INSERT INTO access VALUES('kTCCServiceCamera','org.example.demo',0,1);")
        XCTAssertTrue(try XCTUnwrap(ApplicationPermissionStore.read(path: old, system: false).first).granted)
        let unknown = root.appendingPathComponent("unknown.db").path
        try database(unknown, sql: "CREATE TABLE access(unexpected TEXT);")
        XCTAssertThrowsError(try ApplicationPermissionStore.read(path: unknown, system: false))
        let missing = root.appendingPathComponent("missing.db").path
        XCTAssertThrowsError(try ApplicationPermissionStore.read(path: missing, system: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing), "Le lecteur ne doit jamais créer une base")
    }

    func testPermissionResetIsNarrowAndRefusesSystemManagedAndMalformedClients() throws {
        var calls: [(String, [String])] = []
        let camera = permission()
        try ApplicationPermissionStore.reset(camera) { executable, arguments in
            calls.append((executable, arguments)); return .init(status: 0, stdout: "", stderr: "")
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0, "/usr/bin/tccutil")
        XCTAssertEqual(calls[0].1, ["reset", "Camera", "org.example.demo"])
        for entry in [permission(system: true), permission(managed: true), permission(client: "org.demo; echo invalid"), permission(service: "kTCCServiceAll")] {
            XCTAssertThrowsError(try ApplicationPermissionStore.reset(entry) { _, _ in
                XCTFail("Une entrée refusée ne doit lancer aucune commande")
                return .init(status: 0, stdout: "", stderr: "")
            })
        }
        XCTAssertThrowsError(try ApplicationPermissionStore.reset(camera) { _, _ in .init(status: 1, stdout: "", stderr: "fixture denied") })
    }

    func testAICatalogSeparatesHistoryAndModelsWithoutOfferingCredentialsOrRoots() throws {
        let home = try fixture()
        defer { try? FileManager.default.removeItem(at: home) }
        let model = home.appendingPathComponent(".lmstudio/models/author/model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let catalog = AIClutterCatalog.locations(home: home)
        XCTAssertEqual(Set(catalog.map(\.path)).count, catalog.count)
        XCTAssertTrue(catalog.contains { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == model.resolvingSymlinksInPath().path && $0.group == .models })
        XCTAssertTrue(catalog.contains { $0.path.hasSuffix(".ollama/models") && $0.group == .models })
        XCTAssertTrue(catalog.contains { $0.path.hasSuffix(".codex/sessions") && $0.group == .history })
        for value in catalog {
            XCTAssertFalse([".codex", ".claude", ".gemini", ".ollama", ".lmstudio"].contains(URL(fileURLWithPath: value.path).lastPathComponent))
            XCTAssertFalse(value.path.contains("auth.json"))
            XCTAssertFalse(value.path.contains("credentials"))
        }
        for a in catalog { for b in catalog where a.path != b.path { XCTAssertFalse(a.path.hasPrefix(b.path + "/")) } }
    }

    @MainActor func testAIScanRejectsOutOfCatalogItemsAndStartsUnselected() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let known = root.appendingPathComponent(".codex/log").path
        let forged = root.appendingPathComponent(".codex/auth.json").path
        let model = AIClutterModel(home: root, inspect: { _ in
            [known, forged].map { .init(id: $0, path: $0, category: "aiClutter", size_bytes: 100, reason: "QA", autoselect: true, identity: .init(device: 1, inode: 1), owner: nil) }
        })
        model.scan()
        for _ in 0..<200 {
            if !model.isScanning { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(model.hasScanned)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.items.map(\.path), [known])
        XCTAssertTrue(model.selection.isEmpty)
    }

    private func permission(system: Bool = false, managed: Bool = false, client: String = "org.example.demo", service: String = "kTCCServiceCamera") -> ApplicationPermission {
        .init(service: service, client: client, clientType: 0, authorization: 2, target: "UNUSED", system: system, managed: managed)
    }
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MacCare-NewTools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func database(_ path: String, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "QA", code: 1) }
    }
}
