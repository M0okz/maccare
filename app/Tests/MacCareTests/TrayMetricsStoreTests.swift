import XCTest
import SwiftUI
@testable import MacCare

@MainActor
final class TrayMetricsStoreTests: XCTestCase {
    private func sample(_ time: Double, cpu: Double = 0.2, received: Double = 1000,
                        interface: String = "en0", connected: Bool = true) -> TrayMetrics {
        .init(sampledAt: time, gpu: .init(id: 1, model: "GPU", cores: 8, fraction: cpu),
              fans: .init(fans: [.init(rpm: 1000, maximum: 5000)]), cpu: .init(user: cpu, system: 0),
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

    func testClosingTheLastConsumerKeepsCachedValuesAndHistoryWithoutMonitoring() {
        let store = TrayMetricsStore()
        let dashboard = TrayMetricsStore.Consumer.dashboard(UUID())
        store.setMonitoring(for: dashboard, enabled: true)
        store.record(sample(10))
        store.record(sample(11, cpu: 0.8))
        let displayedCPU = store.snapshot.display.cpu?.used
        store.setMonitoring(for: dashboard, enabled: false)

        XCTAssertFalse(store.isMonitoring)
        XCTAssertEqual(store.snapshot.display.cpu?.used, displayedCPU)
        XCTAssertEqual(store.snapshot.cpu.points.count, 2)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 2)
        XCTAssertEqual(store.snapshot.gpu.points.count, 2)
        XCTAssertEqual(store.snapshot.display.memory?.used, 600)
        XCTAssertEqual(store.snapshot.display.fans?.fastest, 1000)

        store.setMonitoring(for: .menuBar, enabled: true)
        XCTAssertEqual(store.snapshot.display.cpu?.used, displayedCPU)
        XCTAssertEqual(store.snapshot.cpu.points.count, 2)
        store.setMonitoring(for: .menuBar, enabled: false)
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
        XCTAssertEqual(store.snapshot.cpu.points.count, 3)
        XCTAssertEqual(store.snapshot.display.cpu?.used, 0.8)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000)
        var segments = 0
        TrayHistoryPlot(points: store.snapshot.cpu.points, end: 30, duration: 40, maximum: 1, filled: true)
            .path(in: .init(x: 0, y: 0, width: 400, height: 100)).forEach {
                if case .move = $0 { segments += 1 }
            }
        XCTAssertEqual(segments, 2, "La pause reste un trou, sans segment inventé")
    }

    func testResumeKeepsCachedCPUAndNetworkOnlyWhileCountersPrime() {
        let store = TrayMetricsStore()
        store.record(sample(10))
        store.record(sample(11))
        store.stop()
        store.start()
        defer { store.stop() }
        let priming = TrayMetrics(sampledAt: 12, memory: sample(12).memory,
                                  wifi: .init(interface: "en0", powered: true, connected: true,
                                              linkRate: 100, received: nil, sent: nil))
        store.record(priming)
        XCTAssertNil(store.snapshot.raw.cpu)
        XCTAssertNil(store.snapshot.raw.wifi?.received)
        XCTAssertEqual(store.snapshot.display.cpu?.used, 0.2)
        XCTAssertEqual(store.snapshot.display.wifi?.received, 1000)
        XCTAssertEqual(store.snapshot.cpu.points.count, 2)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 2)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000)
        store.record(sample(13, cpu: 0.7, received: 3000))
        XCTAssertEqual(store.snapshot.cpu.points.last?.value, 0.7)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000, "Ne pas compter le trafic pendant la pause")
        for second in 14...20 {
            var unavailable = priming
            unavailable.sampledAt = Double(second)
            store.record(unavailable)
        }
        XCTAssertNil(store.snapshot.display.cpu, "Une panne de lecture ne conserve pas une fausse valeur indéfiniment")
    }

    func testSuspendPreservesCacheAndResumeRespectsRemainingConsumers() {
        let store = TrayMetricsStore()
        let dashboard = TrayMetricsStore.Consumer.dashboard(UUID())
        store.setMonitoring(for: dashboard, enabled: true)
        store.setMonitoring(for: .menuBar, enabled: true)
        store.record(sample(10))
        store.setMonitoring(for: .menuBar, enabled: false)
        XCTAssertTrue(store.isMonitoring)
        store.suspend()
        XCTAssertFalse(store.isMonitoring)
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        store.resume()
        XCTAssertTrue(store.isMonitoring)
        store.setMonitoring(for: dashboard, enabled: false)
        store.resume()
        XCTAssertFalse(store.isMonitoring)
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
    }

    func testSharedCompactNetworkCacheSurvivesNavigationAndInvalidatesOnNewConnection() {
        let store = TrayMetricsStore()
        store.record(sample(10, received: 1000))
        store.record(sample(11, received: 5000))
        XCTAssertEqual(store.snapshot.compactNetwork.wifi?.received, 1000)
        store.stop()
        store.start()
        defer { store.stop() }
        XCTAssertEqual(store.snapshot.compactNetwork.wifi?.received, 1000)
        store.record(.init(sampledAt: 12, wifi: .init(interface: "en1", powered: true, connected: true,
                                                     linkRate: 100, received: nil, sent: nil)))
        XCTAssertEqual(store.snapshot.compactNetwork.wifi?.interface, "en1")
        XCTAssertNil(store.snapshot.display.wifi?.received)
        XCTAssertNil(store.snapshot.compactNetwork.wifi?.received)
        XCTAssertTrue(store.snapshot.traffic.samples.isEmpty)
    }

    func testHistoryCacheHasAHardBoundAndExpiresOldMeasurements() {
        let store = TrayMetricsStore()
        for index in 0..<10_000 { store.record(sample(10 + Double(index) / 10_000)) }
        XCTAssertLessThanOrEqual(store.snapshot.cpu.points.count, 180)
        XCTAssertLessThanOrEqual(store.snapshot.gpu.points.count, 180)
        XCTAssertLessThanOrEqual(store.snapshot.traffic.samples.count, 512)
        store.record(sample(1000))
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 1)
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
        let stoppedAt = store.snapshot.raw.sampledAt
        let historyCount = store.snapshot.cpu.points.count
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(store.snapshot.cpu.points.count, historyCount)
        XCTAssertEqual(store.snapshot.raw.sampledAt, stoppedAt)
        XCTAssertNotNil(store.snapshot.display.cpu)
    }
}
