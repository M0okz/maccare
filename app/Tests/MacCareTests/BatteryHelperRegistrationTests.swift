import Foundation
import ServiceManagement
import Testing
import MacCareBattery
@testable import MacCare

@MainActor
struct BatteryHelperRegistrationTests {
    private final class Client: BatteryClient {
        var status: SMAppService.Status = .requiresApproval
        var statusAfterRegistration: SMAppService.Status = .requiresApproval
        var registrationError: (any Error)?
        var repairError: (any Error)?
        var calls: [String] = []
        var commands: [BatteryCommand] = []
        func register() throws {
            calls.append("register")
            status = statusAfterRegistration
            if let registrationError { throw registrationError }
        }
        func repairHelper() async throws -> HelperUpdateResult {
            calls.append("repair")
            if let repairError { throw repairError }
            status = statusAfterRegistration
            return status == .requiresApproval ? .requiresApproval : .ready
        }
        func openApproval() { calls.append("approval") }
        func snapshot() async -> BatterySnapshot {
            calls.append("snapshot")
            return .init(percent: 53, onAC: false, temperature: 28)
        }
        func prepareProtection() async throws { calls.append("prepareProtection") }
        func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
            commands.append(command)
            var value = BatteryProtectionStatus(snapshot: .init(percent: 53, onAC: false),
                supported: true, active: false, configuration: .init(limit: 80, thermalProtection: false),
                capabilities: .init(backend: .nativeLimit))
            value.recoveryReady = true
            return value
        }
    }

    private func fixture(_ client: Client) throws -> (BatteryModel, UserDefaults, String) {
        let name = testPreferencesSuite("BatteryHelperRegistrationTests")
        let defaults = try #require(UserDefaults(suiteName: name))
        return (BatteryModel(defaults: defaults, monitor: false, client: client), defaults, name)
    }

    @Test func pendingApprovalRetriesRegistrationBeforeOpeningSettings() async throws {
        let client = Client()
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.activateHelper()
        #expect(client.calls.prefix(2) == ["register", "approval"])
        #expect(model.requiresApproval)
        #expect(!model.helperEnabled)
        #expect(client.commands.isEmpty)
    }

    @Test func explicitRetryCanRecoverAnOutdatedApprovalStatus() async throws {
        let client = Client(); client.statusAfterRegistration = .enabled
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.activateHelper()
        #expect(client.calls.first == "register")
        #expect(!client.calls.contains("approval"))
        #expect(model.helperEnabled && !model.requiresApproval)
        #expect(client.commands == [.status])
        #expect(!model.active)
    }

    @Test(arguments: [1, Int(kSMErrorLaunchDeniedByUser), Int(kSMErrorAlreadyRegistered)])
    func deniedRegistrationPreservesTheSystemApprovalStep(_ code: Int) async throws {
        let client = Client(); client.status = .notRegistered
        client.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: code)
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.activateHelper()
        #expect(client.calls.prefix(2) == ["register", "approval"])
        #expect(model.error == nil)
        #expect(model.requiresApproval && !model.helperEnabled)
        #expect(client.commands.isEmpty)
    }

    @Test func aRealRegistrationFailureIsNotHiddenByAnOldApprovalStatus() async throws {
        let client = Client()
        client.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: Int(kSMErrorInvalidSignature))
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.activateHelper()
        #expect(model.error != nil)
        #expect(!client.calls.contains("approval"))
        #expect(client.commands.isEmpty)
    }

    @Test func anEnabledServiceIsOnlyQueriedWithoutReregisteringOrStartingProtection() async throws {
        let client = Client(); client.status = .enabled
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.activateHelper()
        #expect(!client.calls.contains("register"))
        #expect(!client.calls.contains("approval"))
        #expect(client.commands == [.status])
        #expect(!model.active)
    }

    @Test func aTerminatingAppCannotRetryRegistration() async throws {
        let client = Client()
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.prepareForTermination()
        await model.activateHelper()
        #expect(client.calls.isEmpty)
        #expect(client.commands.isEmpty)
    }
    @Test func explicitRepairDoesNotActivateOrEraseTheSavedProtectionIntent() async throws {
        let client = Client(); client.status = .enabled; client.statusAfterRegistration = .enabled
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: BatteryModel.resumeKey)
        await model.repairHelper()
        #expect(client.calls.first == "repair")
        #expect(client.commands == [.status])
        #expect(!model.active)
        #expect(defaults.bool(forKey: BatteryModel.resumeKey))
    }
    @Test func aRepairFailureStaysVisibleWithoutSendingChargeCommands() async throws {
        let client = Client(); client.status = .enabled
        client.repairError = HelperClient.HelperError.unavailable("échec confirmé")
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.repairHelper()
        #expect(model.error?.contains("échec confirmé") == true)
        #expect(client.commands.isEmpty)
    }
    @Test func aTerminatingAppCannotRepairTheRegistration() async throws {
        let client = Client()
        let (model, defaults, name) = try fixture(client)
        defer { defaults.removePersistentDomain(forName: name) }
        await model.prepareForTermination()
        await model.repairHelper()
        #expect(client.calls.isEmpty)
    }

}
