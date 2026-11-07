import Foundation
import Testing
@testable import MacCare

struct DiskHealthTests {
    private let data = Data(#"{"model_name":"Fixture SSD","smart_status":{"passed":true},"temperature":{"current":29},"nvme_smart_health_information_log":{"critical_warning":0,"percentage_used":4,"available_spare":100,"data_units_written":10,"power_on_hours":100,"power_cycles":20,"media_errors":0}}"#.utf8)

    @Test func parsesRealNVMeUnitsAndDoesNotInventRemainingLifetime() throws {
        let report = try DiskHealthReader.parse(data, exitStatus: 0)
        #expect(report.passed == true)
        #expect(report.warning == false)
        #expect(report.temperature == 29)
        #expect(report.enduranceUsed == 4)
        #expect(report.writtenBytes == 5_120_000)
        #expect(report.hours == 100)
    }
    @Test(arguments: [Int32(8), 16, 32, 64, 128])
    func smartctlHealthExitBitsRemainVisibleReports(_ status: Int32) throws {
        let report = try DiskHealthReader.parse(data, exitStatus: status)
        #expect(report.warning)
    }
    @Test(arguments: [Int32(1), 2, 4, -1])
    func commandFailuresDoNotAppearHealthy(_ status: Int32) {
        #expect(throws: DiskHealthReader.ReadError.self) { try DiskHealthReader.parse(data, exitStatus: status) }
    }
    @Test func unsupportedJSONDoesNotProduceFalseZeroValues() {
        #expect(throws: DiskHealthReader.ReadError.self) { try DiskHealthReader.parse(Data("{}".utf8), exitStatus: 0) }
    }
    @Test func mapsAPFSVolumeToItsPhysicalStoreInsteadOfDefaultingToDiskZero() throws {
        let device = try DiskHealthReader.physicalDevice(info: ["DeviceIdentifier":"disk7s1", "APFSPhysicalStores":[["APFSPhysicalStore":"disk4s2"]]]) { path in
            #expect(path == "/dev/disk4s2")
            return ["ParentWholeDisk":"disk4", "VirtualOrPhysical":"Physical"]
        }
        #expect(device == "/dev/disk4")
    }
    @Test func ambiguousAndVirtualVolumesAreUnavailable() {
        for info: [String: Any] in [
            ["APFSPhysicalStores":[["APFSPhysicalStore":"disk0s2"],["APFSPhysicalStore":"disk1s2"]]],
            ["DeviceIdentifier":"disk9", "VirtualOrPhysical":"Virtual"],
            ["ParentWholeDisk":"../../disk0"], [:]
        ] {
            #expect(throws: DiskHealthReader.ReadError.self) {
                try DiskHealthReader.physicalDevice(info: info) { _ in [:] }
            }
        }
    }
}
