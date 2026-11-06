import XCTest
@testable import MacCare

final class TrayIndicatorTests: XCTestCase {
    func testStorageGridRepresentsUsedSpaceAndClampsInvalidFreeSpace() {
        XCTAssertEqual(TrayStorageGrid.occupiedCells(free: 100, total: 100), 0)
        XCTAssertEqual(TrayStorageGrid.occupiedCells(free: 50, total: 100), 36)
        XCTAssertEqual(TrayStorageGrid.occupiedCells(free: 0, total: 100), 72)
        XCTAssertEqual(TrayStorageGrid.occupiedCells(free: 120, total: 100), 0)
        XCTAssertNil(TrayStorageGrid.occupiedCells(free: 0, total: 0))
        XCTAssertEqual(TrayStorageGrid.occupiedCells(free: 0, total: UInt64.max), 72)
    }

    func testNetworkRatesConvertBytesToDecimalMegabits() {
        XCTAssertEqual(NetworkRateFormat.megabits(125_000), "1,00 Mb/s")
        XCTAssertEqual(NetworkRateFormat.megabits(125_000_000), "1000,00 Mb/s")
        XCTAssertEqual(NetworkRateFormat.megabits(0), "0,00 Mb/s")
        XCTAssertEqual(NetworkRateFormat.megabits(nil), "— Mb/s")
        XCTAssertEqual(NetworkRateFormat.megabits(.nan), "— Mb/s")
        XCTAssertEqual(NetworkRateFormat.megabits(-1), "— Mb/s")
    }

    func testPrimaryInterfaceFallsBackToIPv6WithoutGuessingAnActiveAdapter() {
        XCTAssertEqual(NetworkInterfaceSample.primaryName(ipv4: ["PrimaryInterface": "en5"], ipv6: ["PrimaryInterface": "en0"]), "en5")
        XCTAssertEqual(NetworkInterfaceSample.primaryName(ipv4: nil, ipv6: ["PrimaryInterface": "en0"]), "en0")
        XCTAssertNil(NetworkInterfaceSample.primaryName(ipv4: [:], ipv6: nil))
        XCTAssertEqual(NetworkInterfaceSample.kind(name: "utun4", type: nil, wifiName: "en0"), .vpn)
        XCTAssertEqual(NetworkInterfaceSample.kind(name: "en5", type: "Ethernet", wifiName: "en0"), .ethernet)
        XCTAssertEqual(NetworkInterfaceSample.kind(name: "en0", type: nil, wifiName: "en0"), .wifi)
        XCTAssertEqual(NetworkInterfaceSample.kind(name: "bridge7", type: nil, wifiName: "en0"), .other)
    }

    func testAnIPChangeImmediatelyRefreshesTheCompactCard() {
        var readout = TrayNetworkReadout()
        readout.record(.init(sampledAt: 10, wifi: .init(interface: "en0", powered: true, connected: true, linkRate: 100,
                                                      received: 100, sent: 200, address: "192.0.2.1")))
        readout.record(.init(sampledAt: 11, wifi: .init(interface: "en0", powered: true, connected: true, linkRate: 100,
                                                      received: nil, sent: nil, address: "192.0.2.2")))
        XCTAssertEqual(readout.wifi?.address, "192.0.2.2")
        XCTAssertNil(readout.wifi?.received)
    }

    @MainActor func testSmoothingKeepsPressureTemperatureAndInterfaceIdentityCurrent() {
        var smoothing = TrayMetricsSmoothing()
        _ = smoothing.apply(.init(sampledAt: 10, cpu: .init(user: 0.1, system: 0, temperature: 35),
                                  memory: .init(total: 1000, active: 100, wired: 100, compressed: 100, pressure: .normal),
                                  wifi: .init(interface: "en0", powered: true, connected: true, linkRate: 100,
                                              received: 100, sent: 200, address: "192.0.2.1")))
        let next = smoothing.apply(.init(sampledAt: 11, cpu: .init(user: 0.9, system: 0, temperature: 55),
                                        memory: .init(total: 1000, active: 300, wired: 200, compressed: 100, pressure: .critical),
                                        wifi: .init(interface: "en0", powered: true, connected: true, linkRate: 100,
                                                    received: 10, sent: 20, kind: .ethernet, address: "192.0.2.2")))
        XCTAssertEqual(next.memory?.pressure, .critical)
        XCTAssertEqual(next.cpu?.temperature, 55)
        XCTAssertEqual(next.network?.address, "192.0.2.2")
        XCTAssertEqual(next.network?.received, 10)
        XCTAssertEqual(next.network?.kind, .ethernet)
    }
}
