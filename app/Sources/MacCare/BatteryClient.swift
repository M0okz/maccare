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
}
