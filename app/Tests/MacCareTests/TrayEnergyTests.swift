import XCTest
@testable import MacCare

final class TrayEnergyTests: XCTestCase {
    func testTimedCacheReadsOncePerLifetime() {
        var cache = TrayTimedCache<Int>(lifetime: 5)
        var reads = 0
        let read = { () -> Int in reads += 1; return reads }
        XCTAssertEqual(cache.value(now: 100, read: read), 1)
        XCTAssertEqual(cache.value(now: 104.9, read: read), 1)
        XCTAssertEqual(cache.value(now: 105, read: read), 2)
        XCTAssertEqual(reads, 2)
    }

    func testTimedCacheRereadsAfterClearOrWhenTheClockGoesBack() {
        var cache = TrayTimedCache<Int>(lifetime: 5)
        var reads = 0
        let read = { () -> Int in reads += 1; return reads }
        _ = cache.value(now: 100, read: read)
        XCTAssertEqual(cache.value(now: 50, read: read), 2)
        cache.clear()
        XCTAssertEqual(cache.value(now: 51, read: read), 3)
    }

    func testTimedCacheKeepsAnAbsentValue() {
        var cache = TrayTimedCache<Int?>(lifetime: 5)
        var reads = 0
        let read = { () -> Int? in reads += 1; return nil }
        XCTAssertNil(cache.value(now: 1, read: read))
        XCTAssertNil(cache.value(now: 2, read: read))
        XCTAssertEqual(reads, 1, "Un Mac sans Wi-Fi ne doit pas interroger CoreWLAN à chaque seconde")
    }

    func testMemoryRingIgnoresInvisibleVariations() {
        let before = TrayMemoryRingLayout.boundaries([4_000, 3_000, 1_000, 2_000])
        let after = TrayMemoryRingLayout.boundaries([4_001, 2_999, 1_001, 1_999])
        XCTAssertEqual(before, after, "Une variation invisible ne doit pas redessiner l’anneau")
        XCTAssertNotEqual(before, TrayMemoryRingLayout.boundaries([4_500, 2_500, 1_000, 2_000]))
    }

    func testMemoryRingCoversTheWholeCircleWithOrderedBoundaries() {
        let boundaries = TrayMemoryRingLayout.boundaries([1_234, 5_678, 91, 3_210])
        XCTAssertEqual(boundaries.count, 5)
        XCTAssertEqual(boundaries.first, 0)
        XCTAssertEqual(boundaries.last, 1)
        XCTAssertEqual(boundaries, boundaries.sorted())
        XCTAssertEqual(TrayMemoryRingLayout.boundaries([0, 0, 0, 0]), [0, 0, 0, 0, 0])
    }

    func testMemoryRingRoundingStaysInRange() {
        XCTAssertEqual(TrayMemoryRingLayout.rounded(-1), 0)
        XCTAssertEqual(TrayMemoryRingLayout.rounded(2), 1)
        XCTAssertEqual(TrayMemoryRingLayout.rounded(0.504), 0.5)
    }

    @MainActor func testProcessPresentationIsReadOnceAndForgottenWithTheProcess() {
        // Un PID inexistant : aucune application, donc le nom vient du relevé.
        func process(_ name: String) -> TrayProcess {
            .init(id: .init(pid: 999_999, startedSeconds: 1, startedMicroseconds: 2), name: name, userID: getuid(),
                  memory: 1, cpuPercent: nil, executable: "/tmp/test")
        }
        let controller = TrayProcessController()
        XCTAssertEqual(controller.presentation(for: process("premier")).name, "premier")
        controller.record([process("second")])
        XCTAssertEqual(controller.presentation(for: process("second")).name, "premier", "Tant que le processus vit, rien n’est relu")
        controller.record([])
        XCTAssertEqual(controller.presentation(for: process("second")).name, "second", "Un processus disparu sort du cache")
    }

    @MainActor func testProcessRunningAgainUnderTheSamePIDIsReadAgain() {
        let first = TrayProcess(id: .init(pid: 999_999, startedSeconds: 1, startedMicroseconds: 0), name: "ancien", userID: getuid(),
                                memory: 1, cpuPercent: nil, executable: "/tmp/test")
        let second = TrayProcess(id: .init(pid: 999_999, startedSeconds: 2, startedMicroseconds: 0), name: "nouveau", userID: getuid(),
                                 memory: 1, cpuPercent: nil, executable: "/tmp/test")
        let controller = TrayProcessController()
        _ = controller.presentation(for: first)
        XCTAssertEqual(controller.presentation(for: second).name, "nouveau")
    }

    @MainActor func testHiddenConsumersStopTheMeasures() {
        let store = TrayMetricsStore()
        defer { store.stop() }
        let id = UUID()
        store.setMonitoring(for: .activityDetail(id), enabled: true)
        XCTAssertTrue(store.isMonitoring)
        store.setMonitoring(for: .activityDetail(id), enabled: false)
        XCTAssertFalse(store.isMonitoring, "Une fenêtre masquée ne doit plus maintenir les mesures")
    }
}
