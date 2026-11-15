import Foundation
import CMacCareSMC
import Darwin

/// Read-only evidence shared by the CLI and XPC diagnostics. Never creates a
/// controller, touches a recovery journal, or attempts activation to test support.
public struct BatteryFullDiagnostics: Codable, Sendable {
    public let method: String
    public let helperUID: UInt32
    public let snapshot: BatterySnapshot
    public let smc: [BatterySMCKeyDiagnostic]
    public let compatibility: BatteryCompatibilityDiagnostics

    /// Reads battery telemetry, the fixed SMC key matrix, and native capabilities.
    public static func read() -> Self {
        .init(method: "read-only", helperUID: geteuid(), snapshot: .read(),
              smc: BatterySMCKeyDiagnostic.read(), compatibility: .read())
    }
}

/// One raw SMC read attempt. Failed reads remain in the report; their bytes must
/// not be interpreted as a successful zero value. The byte buffer is four bytes.
public struct BatterySMCKeyDiagnostic: Codable, Sendable {
    public let key: String
    public let transport: Int32
    public let handshake: Int32
    public let result: Int32
    public let size: UInt32
    public let type: String
    public let bytes: String

    /// Reads only the ten slots accepted by the C diagnostic bridge, with both
    /// transports and handshakes. Injection is internal and used by unit tests.
    static func read(probe: (Int32, Int32, Int32, UnsafeMutablePointer<MCKeyDiagnostic>) -> Int32
                     = maccare_key_diagnostic) -> [Self] {
        let keys = ["bfF0", "bfD0", "bfE0", "CHTE", "CH0B", "CH0C", "CH0I", "CH0J", "CHIE", "CHLS"]
        var rows: [Self] = []
        for transport: Int32 in [0, 1] {
            for handshake: Int32 in [0, 1] {
                for (index, key) in keys.enumerated() {
                    var field = MCKeyDiagnostic()
                    let result = probe(Int32(index), transport, handshake, &field)
                    let bytes = withUnsafeBytes(of: field.bytes) { $0.map { String(format: "%02x", $0) }.joined() }
                    rows.append(.init(key: key, transport: transport, handshake: handshake, result: result,
                                      size: field.size, type: String(format: "%08x", field.type), bytes: bytes))
                }
            }
        }
        return rows
    }
}
