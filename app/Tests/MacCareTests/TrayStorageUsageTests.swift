import XCTest
@testable import MacCare

final class TrayStorageUsageTests: XCTestCase {
    func testMissingCapacityDoesNotBecomeAnEmptyDisk() {
        XCTAssertNil(TrayStorageUsage(free: 0, total: 0))
        XCTAssertNil(TrayStorageUsage(free: 100, total: 0))
    }

    func testAvailableBeyondCapacityDoesNotUnderflowUsedSpace() throws {
        let usage = try XCTUnwrap(TrayStorageUsage(free: UInt64.max, total: 500))
        XCTAssertEqual(usage.available, 500)
        XCTAssertEqual(usage.used, 0)
        XCTAssertEqual(usage.percent, 0)
    }

    func testVolumesConserveCapacityAndHaveBoundedProgressIncludingUInt64Limits() throws {
        for total in [UInt64(1), 100, 2_000_000_000_000, UInt64.max] {
            for free in [UInt64(0), total / 2, total] {
                let usage = try XCTUnwrap(TrayStorageUsage(free: free, total: total))
                XCTAssertEqual(usage.used + usage.available, total)
                XCTAssertTrue((0...1).contains(usage.fraction))
                XCTAssertTrue((0...100).contains(usage.percent))
            }
        }
        XCTAssertEqual(try XCTUnwrap(TrayStorageUsage(free: 25, total: 100)).percent, 75)
    }
}
