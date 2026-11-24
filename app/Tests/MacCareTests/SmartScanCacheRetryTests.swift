import XCTest
@testable import MacCare

@MainActor
final class SmartScanCacheRetryTests: XCTestCase {
    func testRetryOnlyUsesSelectedOriginalsAndRevalidatesTheirIdentityAndExclusions() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MacCareFixture-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let cache = root.appendingPathComponent("Cache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: false)
        let marker = root.appendingPathComponent("app-open")
        func write(_ name: String) throws -> URL {
            let url = cache.appendingPathComponent(name)
            try Data(repeating: 1, count: 8192).write(to: url, options: .withoutOverwriting)
            return url
        }
        let ready = try write("ready"), occupied = try write("occupied")
        let replaced = try write("replaced"), unchecked = try write("unchecked")
        let excluded = cache.appendingPathComponent("excluded")
        try fm.createDirectory(at: excluded, withIntermediateDirectories: false)
        let keep = excluded.appendingPathComponent("keep")
        try Data(repeating: 1, count: 4096).write(to: keep)
        let suite = testPreferencesSuite("SmartScanCacheRetry")
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set(true, forKey: "directDelete")
        let category = try XCTUnwrap(RuleCatalog.category(fromTOML: """
        id = "cache.fixture"
        category = "user-cache"
        version = 1
        root = "\(tomlEscape(cache.path))"
        depth = "per-app"
        """))
        let model = SmartScanModel(categories: { [category] }, defaults: prefs, makeCacheLookup: {
            { item, _ in
                item.path != ready.path && FileManager.default.fileExists(atPath: marker.path) ? ["App de test"] : []
            }
        })
        model.scan()
        try await finish(model)
        model.toggle(try XCTUnwrap(model.allItems.first { $0.path == unchecked.path }))
        let approved = model.selectedItems
        let expectedBytes = approved.filter { $0.path != ready.path }.reduce(0) { $0 + $1.size_bytes }
        try Data().write(to: marker)
        model.cleanSelected()
        model.cleanSelected()
        model.scan() // un second clic ou un scan concurrent ne remplace pas l’opération.
        try await finish(model)
        XCTAssertFalse(fm.fileExists(atPath: ready.path))
        XCTAssertTrue(fm.fileExists(atPath: occupied.path))
        let first = try XCTUnwrap(model.cleanup)
        XCTAssertEqual(first.report.removed, 1)
        XCTAssertEqual(first.measuredBytes, approved.first { $0.path == ready.path }?.size_bytes)
        XCTAssertEqual(first.appTotals.first?.bytes, expectedBytes)
        XCTAssertEqual(first.waiting.count, 3)
        XCTAssertTrue(first.report.refused.isEmpty && first.report.failed.isEmpty, first.report.summary)
        model.retryPendingCaches()
        try await finish(model)
        XCTAssertEqual(model.cleanup?.waiting.count, 3)
        XCTAssertEqual(model.cleanup?.report.removed, 0)

        let added = try write("after-scan")
        try fm.moveItem(at: replaced, to: root.appendingPathComponent("original"))
        _ = try write("replaced")
        prefs.set([keep.path], forKey: "userExclusions")
        try fm.removeItem(at: marker)
        let scanDate = model.lastCompletedAt
        model.retryPendingCaches()
        try await finish(model)
        XCTAssertEqual(model.lastCompletedAt, scanDate)
        XCTAssertFalse(model.hasPendingCaches)
        let final = try XCTUnwrap(model.cleanup)
        XCTAssertEqual(final.report.removed, 1)
        XCTAssertEqual(Set(final.report.refused.map(\.path)), [replaced.path, excluded.path])
        XCTAssertTrue(final.report.refused.contains { $0.path == replaced.path && $0.reason == "identity-changed" })
        XCTAssertFalse(fm.fileExists(atPath: occupied.path))
        for url in [replaced, excluded, unchecked, added] { XCTAssertTrue(fm.fileExists(atPath: url.path), url.path) }
        model.prepareForNewScan()
        XCTAssertNil(model.cleanup)
    }

    func testRetryKeepsTrashConsentAndRespectsADisabledCategory() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MacCareFixture-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 4, count: 4096).write(to: file)
        let suite = testPreferencesSuite("SmartScanCacheMode")
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set(false, forKey: "directDelete")
        let cat = try XCTUnwrap(RuleCatalog.category(fromTOML: """
        id = "cache.test-mode"
        category = "user-cache"
        version = 1
        root = "\(tomlEscape(root.path))"
        depth = "per-app"
        """))
        var profile = [cat]
        let model = SmartScanModel(categories: { profile }, defaults: prefs, makeCacheLookup: { { _, _ in ["App"] } })
        model.scan()
        try await finish(model)
        model.cleanSelected()
        try await finish(model)
        XCTAssertTrue(model.hasPendingCaches)
        prefs.set(true, forKey: "directDelete")
        model.retryPendingCaches()
        try await finish(model)
        XCTAssertEqual(model.cleanup?.report.direct, false)
        profile = []
        model.retryPendingCaches()
        try await finish(model)
        XCTAssertFalse(model.hasPendingCaches)
        XCTAssertEqual(model.cleanup?.report.refused.map(\.path), [file.path])
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    private func finish(_ model: SmartScanModel) async throws {
        for _ in 0..<500 where model.stage == .scanning || model.stage == .cleaning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.stage, .results)
    }
}
