import XCTest
@testable import MacCare

final class TrayMetricsTests: XCTestCase {
    func testLiveSamplesAndReset() async throws {
        let sampler = TrayMetricsSampler()
        let first = await sampler.sample()
        XCTAssertNil(first.cpu, "Une charge ne peut pas être calculée à partir d’un seul relevé")
        let memory = try XCTUnwrap(first.memory)
        XCTAssertEqual(memory.total, ProcessInfo.processInfo.physicalMemory)
        XCTAssertLessThanOrEqual(memory.used, memory.total)
        XCTAssertEqual(memory.used + memory.available, memory.total)
        try await Task.sleep(for: .seconds(2))
        let second = await sampler.sample()
        let cpu = try XCTUnwrap(second.cpu)
        XCTAssertTrue((0...1).contains(cpu.used))
        if let wifi = second.wifi, wifi.connected {
            if wifi.kind == .wifi { XCTAssertGreaterThan(wifi.linkRate, 0) }
            XCTAssertNotNil(wifi.address)
            if let received = wifi.received { XCTAssertGreaterThanOrEqual(received, 0) }
            if let sent = wifi.sent { XCTAssertGreaterThanOrEqual(sent, 0) }
        }
        await sampler.reset()
        let reset = await sampler.sample()
        XCTAssertNil(reset.cpu)
        XCTAssertNil(reset.wifi?.received)
    }
}
