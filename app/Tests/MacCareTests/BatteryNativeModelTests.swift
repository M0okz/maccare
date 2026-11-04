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
        var failure: String?
        var enableFails = false
        var rootConfiguration: BatteryConfiguration?
        var rootSession: UUID?
        var calls: [BatteryCommand] = []
        var requestedConfigurations: [BatteryConfiguration] = []
        var preparations = 0
        var loadedProtocol: Int?
        var updates = 0
        var approvals = 0
        var updateResult = HelperUpdateResult.ready
        var updateFails = false
        func snapshot() async -> BatterySnapshot { .init(percent: 80, onAC: true, temperature: 30) }
        func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
            calls.append(command)
            if command == .enable && enableFails { throw NSError(domain: "fixture", code: 2) }
            if command == .enable {
                rootActive = true; rootSession = sessionID; rootConfiguration = configuration
                if let configuration { requestedConfigurations.append(configuration) }
            }
            if command == .disable { rootActive = false; restoring = false }
            var value = BatteryProtectionStatus(snapshot: await snapshot(), firmwareManaged: firmwareManaged, supported: true,
                         active: rootActive && !restoring && failure == nil, configuration: rootConfiguration,
                         error: failure ?? (restoring ? "Étalonnage de la batterie en cours" : nil),
                         restoring: restoring, ownedByCaller: rootSession == sessionID, capabilities: capabilities)
            value.recoveryReady = true
            return value
        }
        func prepareProtection() async throws { preparations += 1 }
        func register() throws {}
        func openApproval() { approvals += 1 }
        func loadedHelperProtocolVersion() async throws -> Int? { loadedProtocol }
        func updateHelper() async throws -> HelperUpdateResult {
            updates += 1
            if updateFails { throw NSError(domain: "fixture", code: 1) }
            if updateResult == .ready { loadedProtocol = 10 }
            else { status = .requiresApproval }
            return updateResult
        }
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
    @Test func nativePolicyCapabilitiesPreserveLowerLimitAndSailingDraftWithoutActivation() async throws {
        let client = Client(), initial = BatteryConfiguration(limit: 70, thermalProtection: true, sailingWidth: 5)
        client.capabilities = .init(backend: .nativePolicy)
        let (model, defaults, suite) = try fixture(client, initial: initial)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        #expect(model.nativePolicyControl && model.usesAppleChargeControl)
        #expect(!model.nativeControl && model.supportsThermalProtection && model.supportsSailing)
        #expect(model.availableLimits.contains(70) && model.configuration == initial)
        #expect(client.calls == [.status] && client.preparations == 0 && !client.rootActive)
        #expect(try JSONDecoder().decode(BatteryConfiguration.self, from: #require(defaults.data(forKey: "battery.configuration"))) == initial)
    }
    @Test func oldProtocolRefreshDoesNotReplaceOrActivateHelper() async throws {
        let client = Client(); client.loadedProtocol = 9
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        #expect(model.helperUpdateRequired && model.protection == nil)
        #expect(client.calls.isEmpty && client.updates == 0 && client.preparations == 0)
    }
    @Test func quittingKeepsProtectionForTheNextLaunchWithItsSavedSettings() async throws {
        let client = Client(), settings = BatteryConfiguration(limit: 85, thermalProtection: false)
        let (first, defaults, suite) = try fixture(client, initial: settings)
        defer { defaults.removePersistentDomain(forName: suite) }
        await first.refresh(force: true)
        await first.perform(.enable)
        await first.prepareForTermination()
        #expect(client.calls.last == .disable && !client.rootActive)

        let next = BatteryModel(defaults: defaults, monitor: false, client: client)
        await next.refresh(force: true)
        await next.resumeProtectionIfNeeded()
        #expect(next.active && next.protection?.ownedByCaller == true)
        #expect(client.requestedConfigurations == [settings, settings])
    }
    @Test func anExplicitDeactivationIsNotUndoneAtTheNextLaunch() async throws {
        let client = Client()
        let (first, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await first.perform(.enable)
        await first.perform(.disable)

        let next = BatteryModel(defaults: defaults, monitor: false, client: client)
        await next.refresh(force: true)
        await next.resumeProtectionIfNeeded()
        #expect(!next.active && client.calls.filter { $0 == .enable }.count == 1)
    }
    @Test func aSessionEndedByAnErrorIsNotRestartedAtTheNextLaunch() async throws {
        let client = Client()
        let (first, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await first.perform(.enable)
        client.failure = "Le secteur a disparu."
        await first.refresh(force: true)
        client.failure = nil; client.rootActive = false

        let next = BatteryModel(defaults: defaults, monitor: false, client: client)
        await next.refresh(force: true)
        await next.resumeProtectionIfNeeded()
        #expect(!next.active && client.calls.filter { $0 == .enable }.count == 1)
    }
    @Test func resumeWaitsForTheCurrentHelperAndAnOrphanSessionToEnd() async throws {
        let client = Client(); client.loadedProtocol = 9; client.rootActive = true; client.rootSession = UUID()
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BatteryModel.resumeKey)
        await model.refresh(force: true)
        await model.resumeProtectionIfNeeded()
        #expect(!client.calls.contains(.enable))

        await model.updateHelper()
        await model.resumeProtectionIfNeeded()
        #expect(!client.calls.contains(.enable))

        client.rootActive = false
        await model.refresh(force: true)
        await model.resumeProtectionIfNeeded()
        #expect(client.calls.filter { $0 == .enable }.count == 1 && model.active)
    }
    @Test func aFailedResumeIsTriedOncePerLaunchAndKeepsTheIntent() async throws {
        let client = Client(); client.enableFails = true
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BatteryModel.resumeKey)
        await model.refresh(force: true)
        await model.resumeProtectionIfNeeded()
        #expect(model.error != nil)
        await model.refresh(force: true)
        await model.resumeProtectionIfNeeded()
        #expect(client.calls.filter { $0 == .enable }.count == 1)
        #expect(defaults.bool(forKey: BatteryModel.resumeKey))
    }
    @Test func protectionNeverStartsWithoutAPreviousActivation() async throws {
        let client = Client()
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.resumeProtectionIfNeeded()
        #expect(!client.calls.contains(.enable) && !model.active)
    }
    @Test func helperReplacementIsExplicitAndDoesNotActivateProtection() async throws {
        let client = Client(); client.loadedProtocol = 9
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.updateHelper()
        #expect(client.updates == 1 && model.loadedHelperProtocol == 10)
        #expect(!model.helperUpdateRequired && !model.active)
        #expect(client.calls == [.status] && client.preparations == 0 && client.approvals == 0)
    }
    @Test func helperReplacementApprovalOpensSettingsWithoutStartingControl() async throws {
        let client = Client(); client.loadedProtocol = 9; client.updateResult = .requiresApproval
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.updateHelper()
        #expect(model.requiresApproval && !model.active && client.approvals == 1)
        #expect(client.calls.isEmpty && client.preparations == 0)
    }
    @Test func helperReplacementFailureRemainsVisibleAndNeverActivates() async throws {
        let client = Client(); client.loadedProtocol = 9; client.updateFails = true
        let (model, defaults, suite) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.refresh(force: true)
        await model.updateHelper()
        #expect(model.error != nil && !model.busy && model.helperUpdateRequired)
        #expect(client.calls.isEmpty && client.preparations == 0)
    }
}
