import XCTest
@testable import MacCare

private actor SyntheticSpeedTransport: SpeedTestTransport {
    enum Mode: Sendable { case fast, slow, broken, suspended }
    let mode: Mode
    private(set) var downloads: [Int] = []
    private(set) var uploads: [Int] = []
    private var probes = 0
    init(_ mode: Mode) { self.mode = mode }
    func download(bytes: Int) async throws -> SpeedTransfer {
        downloads.append(bytes)
        if mode == .suspended { try await Task.sleep(for: .seconds(30)) }
        if bytes == 0 {
            probes += 1
            // Première connexion TLS exclue ; médiane des cinq suivantes = 30 ms.
            let times: [Double] = [1, 0.01, 0.05, 0.03, 0.02, 0.04]
            return .init(bytes: 0, seconds: times[min(probes - 1, times.count - 1)])
        }
        if mode == .broken { return .init(bytes: bytes - 1, seconds: 1) }
        return .init(bytes: bytes, seconds: mode == .slow ? 3 : 0.2)
    }
    func upload(bytes: Int) async throws -> SpeedTransfer {
        uploads.append(bytes)
        return .init(bytes: bytes, seconds: mode == .slow ? 3 : 0.2)
    }
}

final class InternetSpeedTests: XCTestCase {
    func testRealByteBudgetMedianAndBothDirections() async throws {
        let transport = SyntheticSpeedTransport(.fast)
        let result = try await InternetSpeedRunner(transport: transport).run { _ in }
        XCTAssertEqual(result.latencyMilliseconds, 30, accuracy: 0.001)
        XCTAssertEqual(result.transferredBytes, 72_000_000)
        XCTAssertEqual(result.downloadMbps, Double(25_000_000) * 8 / 0.2 / 1_000_000, accuracy: 0.01)
        XCTAssertEqual(result.uploadMbps, Double(25_000_000) * 8 / 0.2 / 1_000_000, accuracy: 0.01)
        let downloads = await transport.downloads
        let uploads = await transport.uploads
        XCTAssertEqual(downloads.filter { $0 == 0 }.count, 6)
        XCTAssertEqual(uploads, [1_000_000, 10_000_000, 25_000_000])
    }

    func testSlowLinkStopsEscalatingTransferSizes() async throws {
        let result = try await InternetSpeedRunner(transport: SyntheticSpeedTransport(.slow)).run { _ in }
        XCTAssertEqual(result.transferredBytes, 2_000_000)
    }

    func testIncompleteDownloadCannotProduceSuccessfulResult() async {
        do {
            _ = try await InternetSpeedRunner(transport: SyntheticSpeedTransport(.broken)).run { _ in }
            XCTFail("Un transfert incomplet ne doit pas publier un débit réussi")
        } catch { XCTAssertTrue(error is InternetSpeedError) }
    }

    @MainActor func testCancelAllowsRestartWithoutLateResult() async throws {
        let model = InternetSpeedTest()
        let old = SyntheticSpeedTransport(.suspended)
        model.start(transport: old)
        for _ in 0..<20 {
            if !(await old.downloads).isEmpty { break }
            await Task.yield()
        }
        model.cancel()
        XCTAssertFalse(model.running)
        XCTAssertNil(model.result)
        model.start(transport: SyntheticSpeedTransport(.fast))
        for _ in 0..<100 {
            if model.result != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(model.result)
        XCTAssertFalse(model.running)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.phase, "Test terminé")
    }

    func testWiFiHistoryUsesIntervalsAndResetsOnInterfaceChange() {
        var history = WiFiTrafficHistory()
        func metrics(_ time: Double, _ name: String = "en0", connected: Bool = true) -> TrayMetrics {
            .init(sampledAt: time, wifi: .init(interface: name, powered: true, connected: connected,
                                           linkRate: 100, received: 1000, sent: 500))
        }
        history.record(metrics(10))
        history.record(metrics(12))
        XCTAssertEqual(history.receivedBytes, 2000)
        XCTAssertEqual(history.sentBytes, 1000)
        history.record(metrics(14, "en1"))
        XCTAssertEqual(history.receivedBytes, 0)
        XCTAssertEqual(history.samples.count, 1)
        history.record(metrics(16, "en1", connected: false))
        XCTAssertTrue(history.samples.isEmpty)
    }
}
