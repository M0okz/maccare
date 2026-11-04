import Foundation
import MacCareBattery
import ServiceManagement

@MainActor
protocol BatteryClient {
    var status: SMAppService.Status { get }
    func snapshot() async -> BatterySnapshot
    func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus
    func prepareProtection() async throws
    func register() throws
    func openApproval()
    /// Reads the loaded helper protocol without changing its registration.
    func loadedHelperProtocolVersion() async throws -> Int?
    /// Replaces an older helper only after its battery restoration is confirmed.
    func updateHelper() async throws -> HelperUpdateResult
}

extension BatteryClient {
    // Clients without protocol introspection report an unknown version. Their
    // normal request path remains responsible for validating its own transport.
    func loadedHelperProtocolVersion() async throws -> Int? { nil }
    func updateHelper() async throws -> HelperUpdateResult {
        throw HelperClient.HelperError.unavailable("la mise à jour de l’assistant n’est pas disponible")
    }
}

@MainActor
struct SystemBatteryClient: BatteryClient {
    var status: SMAppService.Status { HelperClient.status }
    func snapshot() async -> BatterySnapshot { await Task.detached(priority: .utility) { BatterySnapshot.read() }.value }
    func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
        try await HelperClient.battery(command, configuration: configuration, sessionID: sessionID)
    }
    func prepareProtection() async throws { try await HelperClient.prepareBatteryProtection() }
    func register() throws { try HelperClient.register() }
    func openApproval() { HelperClient.openApproval() }
    func loadedHelperProtocolVersion() async throws -> Int? { try await HelperClient.loadedProtocolVersion() }
    func updateHelper() async throws -> HelperUpdateResult { try await HelperClient.update() }
}
