import Foundation
import ServiceManagement
import Testing
import MacCareBattery
@testable import MacCare

@MainActor
struct BatteryNativeModelTests {
    private final class Client: BatteryClient {
        var status: SMAppService.Status = .enabled
        var capabilities: BatteryControlCapabilities? = .init(backend: .nativeLimit, supportedLimits: [80, 85, 90, 95, 100])
        var firmwareManaged = false
        var rootActive = false
        var restoring = false
        var rootConfiguration: BatteryConfiguration?
        var rootSession: UUID?
        var calls: [BatteryCommand] = []
        var requestedConfigurations: [BatteryConfiguration] = []
        var preparations = 0
        func snapshot() async -> BatterySnapshot { .init(percent: 80, onAC: true, temperature: 30) }
        func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
            calls.append(command)
            if command == .enable {
                rootActive = true; rootSession = sessionID; rootConfiguration = configuration
                if let configuration { requestedConfigurations.append(configuration) }
            }
            if command == .disable { rootActive = false; restoring = false }
            return .init(snapshot: await snapshot(), firmwareManaged: firmwareManaged, supported: true,
                         active: rootActive && !restoring, configuration: rootConfiguration,
                         error: restoring ? "Étalonnage de la batterie en cours" : nil,
                         restoring: restoring, ownedByCaller: rootSession == sessionID, capabilities: capabilities)
        }
        func prepareProtection() async throws { preparations += 1 }
        func register() throws {}
        func openApproval() {}
    }

    private func fixture(_ client: Client, initial: BatteryConfiguration? = nil) throws -> (BatteryModel, UserDefaults, String) {
        let suite = "MacCareNativeModel.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        if let initial { defaults.set(try JSONEncoder().encode(initial), forKey: "battery.configuration") }
        return (.init(defaults: defaults, monitor: false, client: client), defaults, suite)
    }

    @Test func nativeCapabilitiesAdaptDraftWithoutWritingSettingsOrActivatingControl() async throws {
        let client = Client(), initial = BatteryConfiguration(limit: 65, thermalProtection: true)
        let (model, defaults, suite) = try fixture(client, initial: initial)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        #expect(model.nativeControl)
        #expect(model.supportsThermalProtection == false)
        #expect(model.availableLimits == [80, 85, 90, 95, 100])
        #expect(model.configuration.limit == 80)
        #expect(model.configuration.thermalProtection == false)
        #expect(client.calls == [.status])
        #expect(client.rootActive == false)
        let persisted = try #require(defaults.data(forKey: "battery.configuration"))
        #expect(try JSONDecoder().decode(BatteryConfiguration.self, from: persisted) == initial)
    }

    @Test func legacySwitchCapabilitiesKeepLowerLimitsAndThermalProtection() async throws {
        let client = Client()
        client.capabilities = .init(backend: .legacyPair)
        let (model, defaults, suite) = try fixture(client, initial: .init(limit: 60, thermalProtection: true))
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        #expect(model.nativeControl == false)
        #expect(model.supportsThermalProtection)
        #expect(model.availableLimits.contains(50))
        #expect(model.configuration.limit == 60)
        #expect(model.configuration.thermalProtection)
        #expect(client.calls == [.status])
    }

    @Test func explicitActivationPersistsOnlyTheAdaptedNativeConfiguration() async throws {
        let client = Client()
        let (model, defaults, suite) = try fixture(client, initial: .init(limit: 60, thermalProtection: true))
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.perform(.enable)
        #expect(model.active)
        #expect(client.preparations == 1)
        #expect(client.requestedConfigurations == [.init(limit: 80, thermalProtection: false)])
        let persisted = try #require(defaults.data(forKey: "battery.configuration"))
        #expect(try JSONDecoder().decode(BatteryConfiguration.self, from: persisted) == .init(limit: 80, thermalProtection: false))
        await model.prepareForTermination()
        #expect(client.calls == [.status, .enable, .disable])
    }

    @Test func heartbeatPreservesPendingDraftAndDoesNotApplyItAutomatically() async throws {
        let client = Client()
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.perform(.enable)
        model.configuration.limit = 90
        await model.refresh(force: true)
        #expect(model.configuration.limit == 90)
        #expect(model.pendingChanges)
        #expect(client.requestedConfigurations == [.init(limit: 80, thermalProtection: false)])
        #expect(client.calls == [.status, .enable, .heartbeat])
        await model.prepareForTermination()
    }

    @Test func nativeRestorationStateStopsLeaseRenewalUntilExplicitReactivation() async throws {
        let client = Client()
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.perform(.enable)
        client.restoring = true
        await model.refresh(force: true)
        #expect(model.active == false)
        #expect(model.restoring)
        #expect(model.error != nil)
        await model.refresh(force: true)
        #expect(client.calls == [.status, .enable, .heartbeat, .status])
        #expect(client.requestedConfigurations.count == 1)
        await model.prepareForTermination()
    }

    @Test func olderHelperStatusKeepsFirmwareThermalRestrictionWithoutCapabilities() async throws {
        let client = Client()
        client.capabilities = nil; client.firmwareManaged = true
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        #expect(model.nativeControl == false)
        #expect(model.supportsThermalProtection == false)
        #expect(model.configuration.thermalProtection == false)
        #expect(model.availableLimits == Array(stride(from: 50, through: 100, by: 5)))
    }
}
