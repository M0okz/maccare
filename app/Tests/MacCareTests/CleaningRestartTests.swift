import XCTest
@testable import MacCare

final class CleaningRestartTests: XCTestCase {
    @MainActor
    func testPreparingAnotherAnalysisReturnsToIdleWithoutScanningOrLosingLastCompletedSummary() async throws {
        let suite = testPreferencesSuite("MacCare.CleaningRestartTests")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let category = try category(root: root)
        var categoryReads = 0, completions = 0
        let model = SmartScanModel(categories: { categoryReads += 1; return [category] }, defaults: defaults)
        model.onComplete = { _, _ in completions += 1 }
        model.scan()
        try await finish(model)
        XCTAssertEqual(model.stage, .results)
        XCTAssertFalse(model.groups.isEmpty)
        XCTAssertFalse(model.selection.isEmpty)
        let lastDate = model.lastCompletedAt, lastBytes = model.lastSafeBytes, reads = categoryReads
        let persistedDate = defaults.object(forKey: "lastSmartScanDate") as? Date

        model.prepareForNewScan()

        XCTAssertEqual(model.stage, .idle, "Relancer doit revenir à l’écran Analyser sans lancer le moteur")
        XCTAssertFalse(model.hasRun)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.progress, 0)
        XCTAssertEqual(model.liveEntries, 0)
        XCTAssertEqual(model.liveBytes, 0)
        XCTAssertNil(model.currentLabel)
        XCTAssertNil(model.statusMessage)
        XCTAssertFalse(model.isComplete)
        XCTAssertFalse(model.wasCancelled)
        XCTAssertEqual(categoryReads, reads, "Préparer l’écran ne doit pas relire les catégories pour lancer une analyse")
        try await finish(model)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(model.lastCompletedAt, lastDate)
        XCTAssertEqual(model.lastSafeBytes, lastBytes)
        XCTAssertEqual(defaults.object(forKey: "lastSmartScanDate") as? Date, persistedDate)
    }

    @MainActor
    func testLateScanCompletionCannotReopenResultsAfterPreparingTheIntroduction() async throws {
        let suite = testPreferencesSuite("MacCare.CleaningRestartCancellationTests")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let category = try category(root: root)
        let model = SmartScanModel(categories: { [category] }, defaults: defaults)
        var completions = 0
        model.onComplete = { _, _ in completions += 1 }
        model.scan()
        model.prepareForNewScan()
        // Laisser les callbacks du moteur précédent revenir sur l’acteur principal.
        try await Task.sleep(for: .milliseconds(150))
        try await finish(model)
        XCTAssertEqual(model.stage, .idle)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertEqual(completions, 0)
        XCTAssertNil(model.lastCompletedAt)

        // Le prochain démarrage explicite conserve son fonctionnement normal.
        model.scan()
        try await finish(model)
        XCTAssertEqual(model.stage, .results)
        XCTAssertEqual(completions, 1)
    }

    @MainActor private func finish(_ model: SmartScanModel) async throws {
        for _ in 0..<200 {
            if model.stage != .scanning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La fixture de scan n’a pas terminé")
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("test-app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: folder.appendingPathComponent("cache.bin"))
        return root
    }

    private func category(root: URL) throws -> CleaningCategory {
        try XCTUnwrap(RuleCatalog.category(fromTOML: """
        id = "cache.restart-test"
        category = "user-cache"
        version = 1
        root = "\(tomlEscape(root.path))"
        depth = "per-app"
        title = "Fixture de reprise"
        """))
    }
}
