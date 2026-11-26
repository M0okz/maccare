import XCTest
import SwiftUI
@testable import MacCare

final class ActivityHistoryArchiveTests: XCTestCase {
    private let origin = 1_800_000_000.0
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("history.sqlite") }

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func sample(_ time: Double, _ load: Double, interface: String = "en0") -> TrayMetrics {
        .init(sampledAt: time, gpu: .init(id: 42, model: "GPU", cores: 10, fraction: load),
              cpu: .init(user: load, system: 0), memory: .init(total: 100, active: 40, wired: 10, compressed: 5),
              wifi: .init(interface: interface, powered: true, connected: true, linkRate: 0,
                          received: 1250, sent: 100, address: "192.0.2.1"))
    }

    func testMinuteBatchAndFinalFlushPreserveCountsPeaksAndSeparateRapidRelaunches() async throws {
        let store = ActivityHistoryArchive(url: url)
        for (offset, value) in [(0.0, 0.1), (1, 1), (5, 0.4)] {
            let didWrite = await store.append(sample(offset, value), time: origin + offset, session: 1)
            XCTAssertFalse(didWrite)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let didWrite = await store.append(sample(60, 0.2), time: origin + 60, session: 1)
        XCTAssertTrue(didWrite)
        await store.append(sample(61, 0.6), time: origin + 61, session: 1)
        try await store.flush(now: origin + 61)
        try await store.flush(now: origin + 61)

        let next = ActivityHistoryArchive(url: url)
        await next.append(sample(62, 0.9), time: origin + 62, session: 2)
        try await next.flush(now: origin + 62)
        let history = try await next.recent(now: origin + 63)
        for series in ActivitySeries.allCases { XCTAssertEqual(history[series]?.count, 4) }
        let points = try XCTUnwrap(history[.cpu])
        XCTAssertEqual(points.map(\.count), [2, 1, 2, 1])
        XCTAssertEqual(points.map(\.startsSegment), [true, false, true, true])
        XCTAssertEqual(points[0].value, 0.55, accuracy: 1e-8)
        XCTAssertEqual(points[0].peak, 1)
        XCTAssertEqual(points[2].value, 0.4, accuracy: 1e-8)
        let trend = try await next.trend(.cpu, duration: 86400, end: origin + 63)
        XCTAssertEqual(trend.map(\.session), [1, 2])
        XCTAssertEqual(trend[0].count, 5)
        XCTAssertEqual(trend[0].value, 2.3 / 5, accuracy: 1e-8)
        XCTAssertEqual(trend[0].peak, 1)
    }

    func testRetentionUsesDatesEvenAcrossRebootAndLongInactivity() async throws {
        let store = ActivityHistoryArchive(url: url)
        let days = 86400.0
        for age in [31 * days, 29 * days, 7200, 20] {
            await store.append(sample(1, 0.4), time: origin - age, session: Int64(age))
        }
        try await store.flush(now: origin)
        let reopened = ActivityHistoryArchive(url: url)
        let recent = try await reopened.recent(now: origin)
        XCTAssertEqual(recent[.cpu]?.map(\.time), [origin - 20])
        let month = try await reopened.trend(.cpu, duration: 30 * days, end: origin)
        XCTAssertEqual(month.map(\.time), [origin - 29 * days, origin - 7200, origin - 20])
        XCTAssertTrue(month.allSatisfy(\.startsSegment))
        _ = try await reopened.recent(now: origin + 31 * days)
        let expired = try await reopened.trend(.cpu, duration: 30 * days, end: origin)
        XCTAssertTrue(expired.isEmpty)
    }

    func testFailedBatchRetriesOnceWithoutDoubleCounting() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: url)
        let invalid = url.appendingPathComponent("db")
        let store = ActivityHistoryArchive(url: invalid)
        await store.append(sample(0, 0.7), time: origin, session: 1)
        let wrote = await store.append(sample(60, 0.2), time: origin + 60, session: 1)
        XCTAssertFalse(wrote)
        try FileManager.default.removeItem(at: url)
        try await store.flush(now: origin + 61)
        let reopened = try await store.recent(now: origin + 62)
        XCTAssertEqual(reopened[.cpu]?.map(\.count), [1, 1])
    }

    @MainActor
    func testLiveStoreRestoresWithoutIntegratingTrafficDuringDowntime() async throws {
        let now = Date().timeIntervalSince1970
        let archive = ActivityHistoryArchive(url: url)
        await archive.append(sample(10, 0.8), time: now - 120, session: 5)
        try await archive.flush(now: now)
        let store = TrayMetricsStore(archive: ActivityHistoryArchive(url: url),
                                     sampler: FixedActivitySampler(value: sample(1, 0.3)))
        let ready = expectation(description: "Restored chart and first live sample")
        let observation = store.$snapshot.filter { $0.cpu.points.count == 2 }.prefix(1).sink { _ in ready.fulfill() }
        store.start()
        await fulfillment(of: [ready], timeout: 4)
        await store.prepareForTermination()
        withExtendedLifetime(observation) {}
        XCTAssertEqual(store.snapshot.cpu.points.map(\.value), [0.8, 0.3])
        XCTAssertEqual(store.snapshot.gpu.points.map(\.value), [0.8, 0.3])
        XCTAssertEqual(store.snapshot.traffic.received.points.count, 2)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 0)
        XCTAssertTrue(store.snapshot.cpu.points[1].startsSegment)
        let afterQuit = try await archive.recent(now: Date().timeIntervalSince1970)
        XCTAssertEqual(afterQuit[.cpu]?.count, 2)
        let plot = TrayHistoryPlot(points: store.snapshot.cpu.points, end: now + 1, duration: 600, maximum: 1, filled: true)
        var segments = 0
        plot.path(in: CGRect(x: 0, y: 0, width: 300, height: 100)).forEach { if case .move = $0 { segments += 1 } }
        XCTAssertEqual(segments, 2)
        let clipped = TrayHistoryChart.clipLeadingSegment(store.snapshot.cpu.points, at: now - 30)
        XCTAssertEqual(clipped.count, 1)
    }

    func testRestoredNetworkAndGPUResetOnSourceChange() {
        let old = sample(10, 0.2)
        let rx = TrayHistoryPoint(time: origin - 30, value: 100, source: old.wifi!.historySource)
        let gpu = TrayHistoryPoint(time: origin - 30, value: 0.9, source: 42)
        var network = WiFiTrafficHistory()
        var graphics = TrayGPUHistory()
        network.restore(received: [rx], sent: [rx])
        graphics.restore([gpu])
        var changed = sample(11, 0.3, interface: "en1")
        changed.gpu = .init(id: 43, model: "Other GPU", cores: 8, fraction: 0.3)
        network.record(changed, time: origin, session: 2)
        graphics.record(changed, time: origin, session: 2)
        XCTAssertEqual(network.received.points.map(\.time), [origin])
        XCTAssertEqual(network.receivedBytes, 0)
        XCTAssertEqual(graphics.points.map(\.value), [0.3])
    }

    @MainActor
    func testDashboardUpdatesAtFiveSecondsWhileLivePeakSurvives() {
        let store = TrayMetricsStore()
        for second in 10...15 {
            store.record(sample(Double(second), second == 12 ? 1 : 0.2))
            XCTAssertEqual(store.snapshot.raw.sampledAt, Double(second))
            XCTAssertEqual(store.home.snapshot.raw.sampledAt, second == 15 ? 15 : 10)
        }
        XCTAssertEqual(store.home.snapshot.cpu.points.first?.peak, 1)
    }
}

private actor FixedActivitySampler: TrayMetricsSampling {
    let value: TrayMetrics
    init(value: TrayMetrics) { self.value = value }
    func reset() {}
    func sample(includeSensors: Bool) -> TrayMetrics { value }
}
