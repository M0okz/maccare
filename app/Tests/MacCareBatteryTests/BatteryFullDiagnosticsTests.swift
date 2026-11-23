import Foundation
import Testing
import CMacCareSMC
@testable import MacCareBattery

struct BatteryFullDiagnosticsTests {
    @Test func retainsEveryAttemptIncludingCHIEFailures() throws {
        var attempts: Set<String> = []
        let rows = BatterySMCKeyDiagnostic.read { slot, transport, handshake, field in
            attempts.insert("\(slot)/\(transport)/\(handshake)")
            if slot == 8 && handshake == 1 {
                field.pointee.size = 1
                field.pointee.type = 0x6865785f // hex_
                field.pointee.bytes = (0x08, 0x00, 0xab, 0xff)
                return 0
            }
            return -42
        }
        #expect(attempts.count == 40)
        #expect(rows.count == 40)
        #expect(Set(rows.map(\.key)) == ["bfF0", "bfD0", "bfE0", "CHTE", "CH0B", "CH0C", "CH0I", "CH0J", "CHIE", "CHLS"])
        let chie = rows.filter { $0.key == "CHIE" }
        #expect(chie.count == 4)
        #expect(Set(chie.map { "\($0.transport)/\($0.handshake)" }) == ["0/0", "0/1", "1/0", "1/1"])
        for row in chie where row.handshake == 1 {
            #expect(row.result == 0)
            #expect(row.size == 1)
            #expect(row.type == "6865785f")
            #expect(row.bytes == "0800abff")
        }
        for row in rows where row.result != 0 {
            #expect(row.result == -42)
            #expect(row.size == 0)
            #expect(row.bytes == "00000000")
        }
        // JSON preserves numeric error codes and raw hexadecimal bytes for shell consumers.
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rows)) as? [[String: Any]])
        let failedCHIE = try #require(json.first { $0["key"] as? String == "CHIE" && $0["handshake"] as? Int == 0 })
        #expect(failedCHIE["result"] as? Int == -42)
        #expect(failedCHIE["bytes"] as? String == "00000000")
    }
}
