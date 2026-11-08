import XCTest
@testable import MacCare

final class SpaceExplorerTests: XCTestCase {
    private final class Fixture: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func measure(_ path: String) -> [SpaceChild] {
            lock.lock(); calls += 1; lock.unlock()
            return [SpaceChild(path: path + "/QA-folder", size_bytes: 4096, is_dir: true, measured: true)]
        }
    }

    @MainActor private func finish(_ model: SpaceModel) async throws {
        for _ in 0..<200 {
            if !model.isLoading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("La mesure de test ne se termine pas")
    }

    @MainActor func testExplicitStartCachedParentAndRefresh() async throws {
        let fixture = Fixture()
        let model = SpaceModel(measure: { path, _ in fixture.measure(path) })
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasMeasured)
        XCTAssertEqual(fixture.count, 0)
        model.load()
        try await finish(model)
        let rootDate = model.lastMeasuredAt
        let child = try XCTUnwrap(model.children.first)
        model.open(child)
        try await finish(model)
        XCTAssertEqual(fixture.count, 2)
        model.goUp()
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.lastMeasuredAt, rootDate)
        XCTAssertEqual(fixture.count, 2)
        model.load()
        try await finish(model)
        XCTAssertEqual(fixture.count, 3)
    }

    @MainActor func testCancellationDiscardsLateResultAndForeignNavigation() async throws {
        let model = SpaceModel(measure: { path, _ in
            Thread.sleep(forTimeInterval: 0.05)
            return [SpaceChild(path: path + "/QA-file", size_bytes: 100, is_dir: false, measured: true)]
        })
        let start = model.currentPath
        model.open(SpaceChild(path: "/unrelated", size_bytes: 1, is_dir: true, measured: true))
        XCTAssertEqual(model.currentPath, start)
        model.load()
        model.cancelMeasurement()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasMeasured)
        XCTAssertTrue(model.children.isEmpty)
        XCTAssertNotNil(model.statusMessage)
    }

    @MainActor func testDiskRootIsAvailableWithoutAutomaticMeasurement() {
        let model = SpaceModel(measure: { _, _ in XCTFail("Aucune mesure automatique"); return [] })
        XCTAssertTrue(model.roots.contains { $0.path == "/" })
        let disk = model.roots.first { $0.path == "/" }!
        model.setRoot(disk, measure: false)
        XCTAssertTrue(model.isDiskRoot)
        XCTAssertFalse(model.hasMeasured)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.canRemove(SpaceChild(path: "/Applications/QA.app", size_bytes: 1, is_dir: true, measured: true)))
    }

    @MainActor func testExplicitFolderChoicePreservesRootAndStartsOnlyOnRequest() async throws {
        let fixture = Fixture()
        let model = SpaceModel(measure: { path, _ in fixture.measure(path) })
        // Dossier existant utilisé pour son identité seulement ; le contenu reste injecté.
        model.selectFolder(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        XCTAssertEqual(fixture.count, 0)
        XCTAssertFalse(model.isLoading)
        let chosenPath = model.root.path
        XCTAssertTrue(model.roots.contains { $0.path == chosenPath })
        model.load()
        try await finish(model)
        XCTAssertEqual(fixture.count, 1)
        XCTAssertTrue(model.hasMeasured)
        XCTAssertFalse(model.canRemove(try XCTUnwrap(model.children.first)))
        model.returnToStart()
        XCTAssertEqual(model.root.path, chosenPath)
        XCTAssertFalse(model.hasMeasured)
    }

    func testMapPackingPreservesBoundsAndAvoidsOverlap() {
        let children = (1...30).map { SpaceChild(path: "/QA/\($0)", size_bytes: UInt64($0 * 100), is_dir: true, measured: true) }
            + [SpaceChild(path: "/QA/unknown", size_bytes: 0, is_dir: true, measured: false)]
        for size in [CGSize(width: 350, height: 300), CGSize(width: 750, height: 400)] {
            let packed = BubblePacker.pack(children, in: size)
            XCTAssertFalse(packed.isEmpty)
            XCTAssertLessThanOrEqual(packed.count, 16)
            XCTAssertEqual(packed.map(\.id), BubblePacker.pack(children.reversed(), in: size).map(\.id))
            for (index, bubble) in packed.enumerated() {
                XCTAssertEqual(BubbleHitTest.path(at: bubble.center, in: packed), bubble.id)
                XCTAssertGreaterThan(bubble.child.size_bytes, 0)
                XCTAssertGreaterThanOrEqual(bubble.center.x - bubble.radius, 0)
                XCTAssertLessThanOrEqual(bubble.center.x + bubble.radius, size.width)
                XCTAssertGreaterThanOrEqual(bubble.center.y - bubble.radius, 0)
                XCTAssertLessThanOrEqual(bubble.center.y + bubble.radius, size.height)
                for other in packed.dropFirst(index + 1) {
                    let distance = hypot(bubble.center.x - other.center.x, bubble.center.y - other.center.y)
                    XCTAssertGreaterThanOrEqual(distance, bubble.radius + other.radius)
                }
            }
        }
    }

    func testBubbleHoverFollowsVisibleCirclesInsteadOfTheirBoundingBoxes() {
        let alpha = SpaceChild(path: "/QA/Alpha", size_bytes: 100, is_dir: true, measured: true)
        let beta = SpaceChild(path: "/QA/Beta", size_bytes: 50, is_dir: true, measured: true)
        let bubbles = [PackedBubble(child: alpha, center: .init(x: 60, y: 60), radius: 40),
                       PackedBubble(child: beta, center: .init(x: 150, y: 70), radius: 20)]
        XCTAssertEqual(BubbleHitTest.path(at: .init(x: 60, y: 60), in: bubbles), alpha.id)
        XCTAssertEqual(BubbleHitTest.path(at: .init(x: 150, y: 70), in: bubbles), beta.id)
        XCTAssertEqual(BubbleHitTest.path(at: .init(x: 100, y: 60), in: bubbles), alpha.id)
        XCTAssertNil(BubbleHitTest.path(at: .init(x: 21, y: 21), in: bubbles), "Le coin du cadre et l’ombre ne sont pas la bulle")
        XCTAssertNil(BubbleHitTest.path(at: .init(x: 110, y: 70), in: bubbles), "L’espace entre les bulles ne survole aucun dossier")
        XCTAssertNil(BubbleHitTest.path(at: .init(x: -1, y: -1), in: bubbles))
        XCTAssertNil(BubbleHitTest.path(at: .zero, in: []))
    }

    @MainActor func testSelectingABubbleDoesNotOpenItsFolderUntilExplicitActivation() async throws {
        let fixture = Fixture()
        let model = SpaceModel(measure: { path, _ in fixture.measure(path) })
        model.load()
        try await finish(model)
        let start = model.currentPath
        let child = try XCTUnwrap(model.children.first)
        model.select(child)
        XCTAssertEqual(model.currentPath, start)
        XCTAssertEqual(model.selectedPath, child.id)
        XCTAssertEqual(fixture.count, 1)
        model.open(child)
        try await finish(model)
        XCTAssertEqual(model.currentPath, child.path)
        XCTAssertEqual(fixture.count, 2)
        XCTAssertNil(model.selectedPath)
    }

    @MainActor func testLateHoverExitsDoNotClearTheNewMapOrListTarget() async throws {
        let model = SpaceModel(measure: { path, _ in
            [SpaceChild(path: path + "/Alpha", size_bytes: 100, is_dir: true, measured: true),
             SpaceChild(path: path + "/Beta", size_bytes: 50, is_dir: true, measured: true)]
        })
        model.load()
        try await finish(model)
        let alpha = model.children[0].id, beta = model.children[1].id
        model.highlight(alpha, from: .row(alpha))
        model.highlight(alpha, from: .map)
        model.highlight(nil, from: .row(alpha))
        XCTAssertEqual(model.highlightedPath, alpha)
        model.highlight(alpha, from: .row(alpha))
        model.highlight(nil, from: .map)
        XCTAssertEqual(model.highlightedPath, alpha)
        model.highlight(beta, from: .row(beta))
        model.highlight(nil, from: .row(alpha))
        XCTAssertEqual(model.highlightedPath, beta)
        model.highlight(nil, from: .row(beta))
        XCTAssertNil(model.highlightedPath)
        model.highlight("/outside", from: .map)
        XCTAssertNil(model.highlightedPath)
    }
}
