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
        for second in 0...7200 { history.record(sample(Double(second))) }
        XCTAssertEqual(history.points.first?.time, 3604)
        XCTAssertEqual(history.points.last?.time, 7200)
        XCTAssertEqual(history.points.count, TrayHistoryPoint.maximumCount)
        XCTAssertEqual(TrayMetricHistory.window(history.points, duration: 600).count, 122)
    }

    func testClosingTheLastConsumerKeepsBackgroundMonitoring() {
        let store = TrayMetricsStore()
        let dashboard = TrayMetricsStore.Consumer.dashboard(UUID())
        store.setMonitoring(for: dashboard, enabled: true)
        store.record(sample(10))
        store.record(sample(11, cpu: 0.8))
        let displayedCPU = store.snapshot.display.cpu?.used
        store.setMonitoring(for: dashboard, enabled: false)

        defer { store.stop() }
        XCTAssertTrue(store.isMonitoring)
        XCTAssertEqual(store.snapshot.display.cpu?.used, displayedCPU)
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 1)
        XCTAssertEqual(store.snapshot.gpu.points.count, 1)
        XCTAssertEqual(store.snapshot.display.memory?.used, 600)
        XCTAssertEqual(store.snapshot.display.fans?.fastest, 1000)

        store.setMonitoring(for: .menuBar, enabled: true)
        XCTAssertEqual(store.snapshot.display.cpu?.used, displayedCPU)
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        store.setMonitoring(for: .menuBar, enabled: false)
    }

    func testSmoothingDoesNotAlterHistoryOrTransferredBytes() throws {
        let store = TrayMetricsStore()
        store.record(sample(10, cpu: 0.2))
        store.record(sample(11, cpu: 0.8, received: 5000))
        let displayed = try XCTUnwrap(store.snapshot.display.cpu?.used)
        XCTAssertGreaterThan(displayed, 0.2)
        XCTAssertLessThan(displayed, 0.8)
        XCTAssertEqual(store.snapshot.cpu.points.last?.value, 0.5)
        XCTAssertEqual(store.snapshot.cpu.points.last?.peak, 0.8)
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

    func testHistoryConnectsRealMeasurementsAcrossVisibilityChanges() {
        let store = TrayMetricsStore()
        store.record(sample(10))
        store.record(sample(11))
        store.record(sample(30, cpu: 0.8))
        XCTAssertEqual(store.snapshot.cpu.points.count, 2)
        XCTAssertEqual(store.snapshot.display.cpu?.used, 0.8)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000)
        var segments = 0
        TrayHistoryPlot(points: store.snapshot.cpu.points, end: 30, duration: 40, maximum: 1, filled: true)
            .path(in: .init(x: 0, y: 0, width: 400, height: 100)).forEach {
                if case .move = $0 { segments += 1 }
            }
        XCTAssertEqual(segments, 1, "Relier les relevés réels sans interruption visuelle")
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
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 1)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000)
        store.record(sample(13, cpu: 0.7, received: 3000))
        XCTAssertEqual(store.snapshot.cpu.points.last?.peak, 0.7)
        XCTAssertEqual(store.snapshot.traffic.receivedBytes, 1000, "Ne pas compter le trafic pendant la pause")
        for second in 14...20 {
            var unavailable = priming
            unavailable.sampledAt = Double(second)
            store.record(unavailable)
        }
        XCTAssertNil(store.snapshot.display.cpu, "Une panne de lecture ne conserve pas une fausse valeur indéfiniment")
    }

    func testSuspendPreservesCacheAndResumeReturnsToBackground() {
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
        XCTAssertTrue(store.isMonitoring)
        XCTAssertFalse(store.isForeground)
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        store.stop()
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
        XCTAssertLessThanOrEqual(store.snapshot.cpu.points.count, TrayHistoryPoint.maximumCount)
        XCTAssertLessThanOrEqual(store.snapshot.gpu.points.count, TrayHistoryPoint.maximumCount)
        XCTAssertLessThanOrEqual(store.snapshot.traffic.samples.count, TrayHistoryPoint.maximumCount)
        store.record(sample(5000))
        XCTAssertEqual(store.snapshot.cpu.points.count, 1)
        XCTAssertEqual(store.snapshot.traffic.samples.count, 1)
    }

    func testWiFiWindowUsesTimeInsteadOfTheOldTwoSecondCadence() {
        var history = WiFiTrafficHistory()
        for second in 0...130 { history.record(sample(Double(second))) }
        XCTAssertEqual(history.samples.first?.time, 4)
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
        store.setMonitoring(for: .menuBar, enabled: true)
        store.start()
        defer { store.stop() }
        try await Task.sleep(for: .milliseconds(3300))
        XCTAssertGreaterThanOrEqual(store.snapshot.cpu.points.count, 1)
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

private actor MetricsSamplerProbe: TrayMetricsSampling {
    private(set) var modes: [Bool] = []
    private(set) var resets = 0
    func reset() { resets += 1 }
    func sample(includeSensors: Bool) -> TrayMetrics {
        modes.append(includeSensors)
        return .init(sampledAt: Double(modes.count * 5), cpu: .init(user: 0.2, system: 0))
    }
}

private actor MetricsSleepProbe {
    private(set) var delays: [Duration] = []
    private let entered: @Sendable (Int) -> Void
    init(entered: @escaping @Sendable (Int) -> Void) { self.entered = entered }
    func sleep(_ delay: Duration) async throws {
        delays.append(delay)
        entered(delays.count)
        try await Task.sleep(for: .seconds(3600))
    }
}

extension TrayMetricsStoreTests {
    func testOneSamplerChangesCadenceWithoutResettingOnNavigation() async throws {
        let sampler = MetricsSamplerProbe()
        let events = (1...4).map { expectation(description: "Délai de suivi \($0)") }
        let sleeper = MetricsSleepProbe { index in
            if index <= events.count { events[index - 1].fulfill() }
        }
        let store = TrayMetricsStore(sampler: sampler, sleep: { try await sleeper.sleep($0) })
        defer { store.stop() }
        store.start()
        store.start()
        await fulfillment(of: [events[0]], timeout: 3)
        let firstDelays = await sleeper.delays
        XCTAssertEqual(firstDelays, [.seconds(5)])
        store.setMonitoring(for: .menuBar, enabled: true)
        await fulfillment(of: [events[1]], timeout: 3)
        store.setMonitoring(for: .menuBar, enabled: false)
        await fulfillment(of: [events[2]], timeout: 3)
        let modes = await sampler.modes
        let resets = await sampler.resets
        let delays = await sleeper.delays
        XCTAssertEqual(modes, [false, true, false])
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(delays, [.seconds(5), .seconds(1), .seconds(5)])
        XCTAssertEqual(store.snapshot.cpu.points.count, 3)
        store.suspend()
        XCTAssertFalse(store.isMonitoring)
        store.resume()
        await fulfillment(of: [events[3]], timeout: 3)
        let resumedResets = await sampler.resets
        XCTAssertEqual(resumedResets, 2, "La veille réamorce les compteurs, la navigation ne le fait pas")
        store.stop()
        store.resume()
        XCTAssertFalse(store.isMonitoring)
    }

    func testAggregationKeepsPeaksWithoutInventingSamples() throws {
        var history = TrayMetricHistory()
        history.record(time: 10, value: 0.1)
        history.record(time: 11, value: 0.9)
        history.record(time: 14, value: 0.2)
        history.record(time: 20, value: nil)
        history.record(time: 25, value: 0.4)
        XCTAssertEqual(history.points.count, 2)
        XCTAssertEqual(history.points.first?.time, 14)
        XCTAssertEqual(try XCTUnwrap(history.points.first?.value), 0.4, accuracy: 0.00001)
        let stats = TrayMetricHistory.statistics(history.points, duration: 600)
        XCTAssertEqual(try XCTUnwrap(stats.average), 0.4, accuracy: 0.00001)
        XCTAssertEqual(stats.peak, 0.9)
    }

    func testCompactCPUAndGPUSlowDownButPressureAndTemperatureStayImmediate() throws {
        let store = TrayMetricsStore()
        store.record(sample(10, cpu: 0.2))
        var next = sample(11, cpu: 0.8)
        next.cpu?.temperature = 90
        next.memory?.pressure = .critical
        store.record(next)
        XCTAssertEqual(store.snapshot.compact.metrics.cpu?.used, 0.2)
        XCTAssertEqual(store.snapshot.compact.metrics.gpu?.fraction, 0.2)
        XCTAssertEqual(store.snapshot.compact.metrics.memory?.pressure, .critical)
        XCTAssertEqual(store.snapshot.compact.metrics.cpu?.temperature, 90)
        XCTAssertEqual(try XCTUnwrap(store.snapshot.display.gpu?.fraction), 0.2 + 0.6 * (1 - exp(-1.0 / 5)), accuracy: 0.00001)
        store.record(sample(13, cpu: 0.8))
        XCTAssertGreaterThan(try XCTUnwrap(store.snapshot.compact.metrics.cpu?.used), 0.2)
        XCTAssertEqual(store.snapshot.cpu.points.last?.peak, 0.8)
        store.record(sample(14, connected: false))
        XCTAssertFalse(store.snapshot.compact.metrics.wifi?.connected ?? true)
        store.record(.init(sampledAt: 14.5))
        XCTAssertNil(store.snapshot.compact.metrics.wifi)
    }

    func testBackgroundNetworkCounterAndVolumesCoverRealFiveSecondIntervals() {
        var counter = TrayNetworkCounter()
        func reading(_ time: Double, received: UInt32, address: String = "10.0.0.1") -> TrayNetworkCounter.Reading {
            .init(name: "en0", address: address, received: received, sent: received / 2, time: time)
        }
        XCTAssertNil(counter.rates(reading(10, received: 1000)).received)
        XCTAssertEqual(counter.rates(reading(15, received: 26_000)).received, 5000)
        XCTAssertNil(counter.rates(reading(20, received: 30_000, address: "10.0.0.2")).received)
        XCTAssertNil(counter.rates(reading(100, received: 50_000, address: "10.0.0.2")).received)
        var history = WiFiTrafficHistory()
        history.record(sample(10, received: 1000))
        history.record(sample(15, received: 5000))
        XCTAssertEqual(history.receivedBytes, 25_000)
        history.pause()
        history.record(sample(100, received: 10_000))
        XCTAssertEqual(history.receivedBytes, 25_000)
    }

    func testNetworkScaleResistsSmallVariationsAndOnlyShrinksAfterAQuietMinute() {
        var scale = TrayNetworkScale()
        scale.record(peak: 1_000_000, time: 10)
        let high = scale.maximum
        scale.record(peak: 1_010_000, time: 11)
        XCTAssertEqual(scale.maximum, high)
        scale.record(peak: 1000, time: 20)
        scale.record(peak: 1000, time: 79)
        XCTAssertEqual(scale.maximum, high)
        scale.record(peak: 1000, time: 80)
        XCTAssertLessThan(scale.maximum, high)
        scale.record(peak: 10_000_000, time: 81)
        XCTAssertGreaterThan(scale.maximum, high)
    }
}
