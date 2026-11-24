import XCTest
@testable import MacCare

final class SpaceHistoryTests: XCTestCase {
    func testPersistentRotationRanksComparableFoldersAndMarksIncompleteReads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = SpaceHistory.Scope(path: "/fixture", volume: "first", inode: 12)
        func child(_ name: String, _ bytes: UInt64, complete: Bool = true, directory: Bool = true) -> SpaceChild {
            SpaceChild(path: "/fixture/" + name, size_bytes: bytes, is_dir: directory, measured: complete)
        }
        let first = Date(timeIntervalSince1970: 1)
        let initial = [child("A", 1), child("B", 400), child("Refus", 25), child("Rétabli", 0, complete: false),
                       child("Disparu", 8), child("Identique", 10)]
        guard case .baseline = try SpaceHistory(directory: directory).record(initial, date: first, scope: scope) else {
            return XCTFail("Première référence attendue")
        }
        let second = first.addingTimeInterval(1)
        let now = [child("A", 501), child("B", 200), child("Refus", 0, complete: false), child("Rétabli", 25),
                   child("Nouveau", 9), child("Identique", 10), child("fichier", 5000, directory: false)]
        let store = SpaceHistory(directory: directory)
        guard case .compared(let date, let rows) = try store.record(now, date: second, scope: scope) else {
            return XCTFail("La référence doit survivre au changement d’instance")
        }
        XCTAssertEqual(date, first)
        XCTAssertEqual(rows.map(\.name), ["A", "B", "Nouveau", "Disparu", "Refus", "Rétabli"])
        XCTAssertEqual(rows.first?.magnitude, 500)
        XCTAssertFalse(rows[1].growth)
        XCTAssertTrue(rows.suffix(2).allSatisfy { $0.label == "Mesure partielle" })
        guard case .compared(let nextDate, _) = try store.record([], date: second.addingTimeInterval(1), scope: scope)
        else { return XCTFail("Un dossier vide conserve les disparitions") }
        XCTAssertEqual(nextDate, second)
        let file = try Data(contentsOf: directory.appendingPathComponent(scope.filename))
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
        XCTAssertEqual(Set(persisted.keys), ["previous", "latest"])

        for other in [SpaceHistory.Scope(path: scope.path, volume: "other", inode: scope.inode),
                      SpaceHistory.Scope(path: scope.path, volume: scope.volume, inode: 99)] {
            guard case .baseline = try store.record(now, date: second, scope: other) else {
                return XCTFail("Un autre volume ou dossier commence avec sa propre référence")
            }
        }
    }

    @MainActor func testCancelledMeasureAndCachedNavigationDoNotRotateHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("fixture")
        let child = root.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = SpaceModel(history: SpaceHistory(directory: directory.appendingPathComponent("history")), measure: { p, _ in
            Thread.sleep(forTimeInterval: 0.03)
            return p.hasSuffix("/Child") ? [] : [SpaceChild(path: p + "/Child", size_bytes: 12, is_dir: true, measured: true)]
        })
        func finish() async throws {
            for _ in 0..<300 where model.isLoading { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertTrue(model.hasMeasured)
        }
        model.selectFolder(root)
        model.load()
        model.cancelMeasurement()
        model.load()
        try await finish()
        guard case .baseline = model.comparison else { return XCTFail("La mesure annulée ne fournit aucune référence") }
        let date = try XCTUnwrap(model.lastMeasuredAt)
        model.open(try XCTUnwrap(model.children.first))
        try await finish()
        model.goUp()
        guard case .baseline = model.comparison else { return XCTFail("Le retour utilise la mesure en cache") }
        model.load()
        try await finish()
        guard case .compared(let reference, let rows) = model.comparison else { return XCTFail("Comparaison attendue") }
        XCTAssertEqual(reference, date)
        XCTAssertTrue(rows.isEmpty)
    }
}
