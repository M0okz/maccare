import XCTest
@testable import MacCare

@MainActor
final class TrayMetricsStoreTests: XCTestCase {
    private func sample(_ time: Double, cpu: Double = 0.2, received: Double = 1000,
                        interface: String = "en0", connected: Bool = true) -> TrayMetrics {
        .init(sampledAt: time, cpu: .init(user: cpu, system: 0),
              memory: .init(total: 1000, active: 300, wired: 200, compressed: 100),
              wifi: .init(interface: interface, powered: true, connected: connected,
                          linkRate: 100, received: received, sent: 500))
    }

    func testCPUHistoryHasARealBoundedTimeWindow() {
        var history = TrayCPUHistory()
        for second in 0...100 { history.record(sample(Double(second))) }
        XCTAssertEqual(history.points.first?.time, 59)
        XCTAssertEqual(history.points.last?.time, 100)
        XCTAssertEqual(history.points.count, 42, "40 secondes et un segment de bord, pas un historique étiré")
    }

    func testSmoothingDoesNotAlterHistoryOrTransferredBytes() throws {
        let store = TrayMetricsStore()
        store.record(sample(10, cpu: 0.2))
        store.record(sample(11, cpu: 0.8, received: 5000))
        let displayed = try XCTUnwrap(store.snapshot.display.cpu?.used)
        XCTAssertGreaterThan(displayed, 0.2)
        XCTAssertLessThan(displayed, 0.8)
        XCTAssertEqual(store.snapshot.cpu.points.last?.value, 0.8)
        XCTAssertEqual(store.snapshot.raw.wifi?.received, 5000)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 5000)
        XCTAssertLessThan(try XCTUnwrap(store.snapshot.display.wifi?.received), 5000)
    }

    func testChangingInterfaceAndDisconnectingDoNotBlendOldTraffic() {
        let store = TrayMetricsStore()
        store.record(sample(10, received: 100_000))
        store.record(sample(11, received: 10, interface: "en1"))
        XCTAssertEqual(store.snapshot.display.wifi?.received, 10)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 0)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 1)
        store.record(sample(12, interface: "en1", connected: false))
        XCTAssertFalse(store.snapshot.display.wifi?.connected ?? true)
        XCTAssertTrue(store.snapshot.traffic.samples.isEmpty)
    }

    func testSamplingGapDoesNotDrawALineAcrossSuspension() {
        let store = TrayMetricsStore()
        store.record(sample(10))
        store.record(sample(11))
        store.record(sample(30, cpu: 0.8))
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        XCTAssertEqual(store.snapshot.display.cpu?.used, 0.8)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 0)
    }

    func testWiFiWindowUsesTimeInsteadOfTheOldTwoSecondCadence() {
        var history = WiFiTrafficHistory()
        for second in 0...130 { history.record(sample(Double(second))) }
        XCTAssertEqual(history.samples.first?.time, 9)
        XCTAssertEqual(history.samples.last?.time, 130)
        XCTAssertEqual(history.receivedBytes, 130_000)
    }

    func testCompactNetworkReadoutWaitsThreeSecondsWithoutDelayingTheDetail() {
        var readout = TrayNetworkReadout()
        readout.record(sample(10, received: 1000))
        let standardDetailSample = sample(11, received: 5000)
        readout.record(standardDetailSample)
        XCTAssertEqual(readout.wifi?.received, 1000)
        XCTAssertEqual(standardDetailSample.wifi?.received, 5000)
        readout.record(sample(13, received: 8000))
        XCTAssertEqual(readout.wifi?.received, 8000)
        readout.record(sample(14, connected: false))
        XCTAssertFalse(readout.wifi?.connected ?? true)
        readout.record(sample(15, received: 20, interface: "en1"))
        XCTAssertEqual(readout.wifi?.received, 20)
    }

    func testLiveMonitoringWorksWithoutAViewAndCancelsOnStop() async throws {
        let store = TrayMetricsStore()
        store.start()
        store.start()
        defer { store.stop() }
        try await Task.sleep(for: .milliseconds(3300))
        XCTAssertGreaterThanOrEqual(store.snapshot.cpu.points.count, 2)
        XCTAssertNotNil(store.snapshot.display.memory)
        store.stop()
        XCTAssertFalse(store.isMonitoring)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(store.snapshot.cpu.points.isEmpty)
        XCTAssertNil(store.snapshot.display.cpu)
    }
}
