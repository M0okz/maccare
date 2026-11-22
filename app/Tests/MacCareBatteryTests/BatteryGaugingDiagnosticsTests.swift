import Foundation
import Testing
@testable import MacCareBattery

struct BatteryGaugingDiagnosticsTests {
    private func encode(_ info: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["batteryGaugingMitigationInfo": info], format: .binary, options: 0)
    }

    @Test func recordsDatesWithoutSerialsOrAnInferredActivationDecision() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-31T20:34:07Z"))
        let report = BatteryGaugingDiagnostics.parse(try encode([
            "batteryPackData": ["PRIVATE-SERIAL": ["lastDOD0Update": date, "lastQMaxUpdate": date, "lastQualQMaxDate": date,
                                                       "privateField": "PRIVATE-VALUE"]],
            "lastFullChargeDate": date.addingTimeInterval(14 * 86400), "lastFullChargeReq": true,
            "otherPrivateField": "PRIVATE-VALUE"
        ]))
        #expect(report.readState == .available && report.lastFullChargeReq == true)
        #expect(report.packs.count == 1 && report.packs.first?.lastDOD0Update == "2026-10-31T20:34:07Z")
        let text = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!text.contains("PRIVATE") && !text.contains("privateField"))
        // A stale date or recorded request is not the live notification state.
        #expect(!text.contains("activationAllowed") && !text.contains("fullChargeOverride"))
    }

    @Test func missingAndMalformedValuesNeverBecomeAnInactiveAppleRequest() throws {
        let missing = BatteryGaugingDiagnostics.parse(try encode(["batteryPackData": [:]]))
        #expect(missing.readState == .available && missing.lastFullChargeReq == nil && missing.packs.isEmpty)
        for malformed: Any in ["false", 0, ["unexpected": true]] {
            let report = BatteryGaugingDiagnostics.parse(try encode(["batteryPackData": [:], "lastFullChargeReq": malformed]))
            #expect(report.readState == .invalidFormat && report.lastFullChargeReq == nil)
        }
        #expect(BatteryGaugingDiagnostics.parse(Data("invalid".utf8)).readState == .invalidFormat)
        #expect(BatteryGaugingDiagnostics.parse(Data(repeating: 0, count: 65_537)).readState == .tooLarge)
        let wrongDate = BatteryGaugingDiagnostics.parse(try encode(["batteryPackData": ["serial": ["lastDOD0Update": "2030"]]]))
        #expect(wrongDate.readState == .invalidFormat)
    }

    @Test func futureDateIsReportedAsRecordedWithoutClaimingCalibrationFinished() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z"))
        let report = BatteryGaugingDiagnostics.parse(try encode(["batteryPackData": ["serial": ["lastDOD0Update": date]]]))
        #expect(report.packs.first?.lastDOD0Update == "2030-01-01T00:00:00Z")
        #expect(report.lastFullChargeReq == nil)
    }
}
