import Foundation
import AppIntents
import ServiceManagement
import Testing
import MacCareBattery
@testable import MacCare

@MainActor
struct BatteryAutomationTests {
    private final class Client: BatteryClient {
        var status: SMAppService.Status = .enabled
        var commands: [BatteryCommand] = []
        var active = false
        var plugged = true
        var owner = true
        var capabilities = BatteryControlCapabilities(backend: .chargeGate, adapterBackend: .modern)
        var configuration = BatteryConfiguration(thermalProtection: false)
        func snapshot() async -> BatterySnapshot { .init(percent: 80, onAC: plugged, temperature: 28) }
        func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
            commands.append(command)
            if command == .enable { active = true; self.configuration = configuration ?? self.configuration }
            if command == .disable { active = false }
            var value = BatteryProtectionStatus(snapshot: .init(percent: 80, onAC: plugged, temperature: 28), supported: true,
                active: active, configuration: self.configuration, ownedByCaller: active && owner, capabilities: capabilities)
            value.recoveryReady = true
            return value
        }
        func prepareProtection() async throws {}
        func register() throws {}
        func openApproval() {}
    }
    private final class Preferences {
        let name = testPreferencesSuite("BatteryAutomationTests")
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { defaults.removePersistentDomain(forName: name) }
    }
    @Test func dueJobExecutesOnceAndDurableRestartDoesNotRepeatIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = Client(), prefs = Preferences()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client, historyStore: BatteryHistoryStore(directory: directory))
        await model.loadAdvancedData()
        let now = Date()
        await model.saveSchedule(.init(name: "Départ", action: .topUp, recurrence: .once, firstRun: now))
        await model.processSchedules(now: now)
        #expect(client.commands.filter { $0 == .enable }.count == 1)
        #expect(client.commands.filter { $0 == .topUp }.count == 1)
        #expect(model.automationEvents.count == 1)
        let nextClient = Client(), nextPrefs = Preferences()
        let restarted = BatteryModel(defaults: nextPrefs.defaults, monitor: false, client: nextClient, historyStore: BatteryHistoryStore(directory: directory))
        await restarted.loadAdvancedData()
        await restarted.processSchedules(now: now.addingTimeInterval(1))
        #expect(nextClient.commands.isEmpty)
    }
    @Test func noControllerCannotTriggerIsolationOrUnexpectedActivation() async {
        let client = Client(); client.capabilities = .init(backend: .nativeLimit)
        let prefs = Preferences()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client)
        await #expect(throws: (any Error).self) { try await model.executeAutomation(.discharge) }
        #expect(client.commands.allSatisfy { $0 == .status })
        #expect(client.active == false)
    }
    @Test func aCalibrationScheduleSavedByAnEarlierVersionCannotStart() async {
        let client = Client(), prefs = Preferences()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client)
        await #expect(throws: (any Error).self) { try await model.executeAutomation(.calibrate) }
        #expect(!client.commands.contains(.calibrate) && !client.commands.contains(.enable))
        #expect(client.active == false)
    }
    @Test func anotherSessionCannotBeReconfiguredByAnAutomation() async {
        let client = Client(); client.active = true; client.owner = false
        let prefs = Preferences()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client)
        await #expect(throws: (any Error).self) { try await model.executeAutomation(.configure(.init(limit: 70, thermalProtection: false))) }
        #expect(client.commands.allSatisfy { $0 == .status })
    }
    @Test func missedCycleRecordsAnEventWithoutMutatingHardware() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = Client(), prefs = Preferences()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client, historyStore: BatteryHistoryStore(directory: directory))
        await model.loadAdvancedData()
        let due = Date().addingTimeInterval(-3600)
        await model.saveSchedule(.init(name: "Cycle", action: .calibrate, recurrence: .daily, firstRun: due))
        await model.processSchedules(now: .now)
        #expect(client.commands.isEmpty)
        #expect(model.automationEvents.first?.contains("manquée") == true)
    }
    @Test func shortcutIntentUsesTheSameValidationAsTheScreen() async throws {
        let prefs = Preferences(), client = Client()
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client)
        BatteryIntentBridge.bind(model)
        var intent = SetBatteryLimitIntent(); intent.limit = 70
        _ = try await intent.perform()
        #expect(client.configuration.limit == 70)
        #expect(client.commands.filter { $0 == .enable }.count == 1)
        intent.limit = 25
        await #expect(throws: (any Error).self) { try await intent.perform() }
        #expect(client.commands.filter { $0 == .enable }.count == 1)
    }

    @Test func anUnpluggedCalibrationCannotActivateProtectionAsASideEffect() async {
        let prefs = Preferences(), client = Client(); client.plugged = false
        let model = BatteryModel(defaults: prefs.defaults, monitor: false, client: client)
        await #expect(throws: (any Error).self) { try await model.executeAutomation(.calibrate) }
        #expect(client.commands.allSatisfy { $0 == .status })
        #expect(client.active == false)
    }

}
