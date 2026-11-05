import Foundation
import MacCareBattery
import MacCareHelperProtocol
import ServiceManagement
import Testing
@testable import MacCare

@MainActor
struct HelperServiceUpdateTests {
    private enum Failure: Error { case version, battery, unregister, registration, legacy }

    @MainActor private final class Gate {
        private var entered = false
        private var entryWaiter: CheckedContinuation<Void, Never>?
        private var releaseWaiter: CheckedContinuation<Void, Never>?
        func suspend() async {
            entered = true
            entryWaiter?.resume(); entryWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        func waitUntilEntered() async {
            if entered { return }
            await withCheckedContinuation { entryWaiter = $0 }
        }
        func release() { releaseWaiter?.resume(); releaseWaiter = nil }
    }

    private final class Client: HelperServiceLifecycle {
        var status: SMAppService.Status = .enabled
        var version = 9
        var nextVersionBeforeRemoval: Int?
        var statusAfterRegistration: SMAppService.Status = .enabled
        var versionError: (any Error)?
        var batteryError: (any Error)?
        var disableError: (any Error)?
        var unregisterError: (any Error)?
        var registrationError: (any Error)?
        var legacyError: (any Error)?
        var failVersionAfterRegistration = false
        var remainEnabledAfterUnregister = false
        var versionAfterRegistration = HelperIdentity.protocolVersion
        var versionGate: Gate?
        var statusReply = HelperServiceUpdateTests.response(active: false)
        var disableReply = HelperServiceUpdateTests.response(active: false)
        var calls: [String] = []
        var commands: [(BatteryCommand, UUID?)] = []
        private var registered = false
        private var versionReads = 0

        func loadedProtocolVersion() async throws -> Int {
            calls.append("version")
            versionReads += 1
            if let gate = versionGate { versionGate = nil; await gate.suspend() }
            if let versionError { throw versionError }
            if failVersionAfterRegistration && registered { throw Failure.version }
            if versionReads > 1, !registered, let nextVersionBeforeRemoval { return nextVersionBeforeRemoval }
            return version
        }
        func restorationReply(_ command: BatteryCommand, sessionID: UUID?) async throws -> String {
            calls.append(command.rawValue)
            commands.append((command, sessionID))
            if let batteryError { throw batteryError }
            if command == .disable, let disableError { throw disableError }
            return command == .status ? statusReply : disableReply
        }
        func restoreLegacyBattery() async throws {
            calls.append("legacyRestore")
            if let legacyError { throw legacyError }
        }
        func unregister() async throws {
            calls.append("unregister")
            if let unregisterError { throw unregisterError }
            if !remainEnabledAfterUnregister { status = .notRegistered }
        }
        func register() throws {
            calls.append("register")
            status = statusAfterRegistration
            version = versionAfterRegistration
            registered = true
            if let registrationError { throw registrationError }
        }
    }

    nonisolated private static func response(active: Bool, restoring: Bool = false, error: String? = nil) -> String {
        // Real v9 JSON contains more fields than the restoration boundary needs.
        // Its capability shape must not be decoded by the new client here.
        let errorJSON = error.map { "\"\($0)\"" } ?? "null"
        return """
        {"active":\(active),"restoring":\(restoring),"error":\(errorJSON),
         "snapshot":{"present":true,"percent":55,"onAC":true},
         "capabilities":{"backend":4,"supportedLimits":[80,85,90,95,100]},
         "configuration":{"limit":80,"thermalProtection":false}}
        """
    }

    @Test func versionQueryNeverChangesRegistrationOrBatteryState() async throws {
        let client = Client()
        #expect(try await HelperServiceUpdater(client: client).loadedProtocolVersion() == 9)
        #expect(client.calls == ["version"])
        #expect(client.commands.isEmpty)
    }

    @Test func currentHelperIsNotReplacedOrStopped() async throws {
        let client = Client(); client.version = HelperIdentity.protocolVersion
        client.statusReply = Self.response(active: true)
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        #expect(client.calls == ["version"])
        #expect(client.commands.isEmpty)
    }

    @Test func inactiveVersionNineIsConfirmedBeforeReplacement() async throws {
        let client = Client()
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        #expect(client.calls == ["version", "status", "version", "unregister", "register", "version"])
        #expect(client.commands.count == 1)
        #expect(client.commands.first?.0 == .status && client.commands.first?.1 == nil)
    }

    @Test func activeVersionNineIsRestoredThroughItsCompatibleSelector() async throws {
        let client = Client(); client.statusReply = Self.response(active: true)
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        #expect(client.calls == ["version", "status", "disable", "version", "unregister", "register", "version"])
        #expect(client.commands.map(\.0) == [.status, .disable])
        #expect(client.commands.last?.1 != nil)
    }

    @Test(arguments: [Self.response(active: false, restoring: true), Self.response(active: false, error: "restauration en attente")])
    func pendingRestorationIsCompletedBeforeRemoval(_ statusJSON: String) async throws {
        let client = Client(); client.statusReply = statusJSON
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        let restoreIndex = try #require(client.calls.firstIndex(of: "disable"))
        let removalIndex = try #require(client.calls.firstIndex(of: "unregister"))
        #expect(restoreIndex < removalIndex)
    }

    @Test(arguments: [Self.response(active: true), Self.response(active: false, restoring: true), Self.response(active: false, error: "restauration impossible")])
    func unconfirmedRestorationNeverRemovesTheOldService(_ stoppedJSON: String) async {
        let client = Client(); client.statusReply = Self.response(active: true); client.disableReply = stoppedJSON
        await #expect(throws: HelperClient.HelperError.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "disable"])
    }

    @Test(arguments: ["{}", "{\"active\":false}", "not-json"])
    func anUnrecognizedBatteryReplyCannotPermitReplacement(_ json: String) async {
        let client = Client(); client.statusReply = json
        await #expect(throws: (any Error).self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status"])
    }

    @Test func aFailedVersionQueryCannotPermitReplacement() async {
        let client = Client(); client.versionError = Failure.version
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version"])
    }

    @Test func anAmbiguousBatteryRequestCannotPermitReplacement() async {
        let client = Client(); client.batteryError = Failure.battery
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status"])
    }

    @Test func anAmbiguousDisableReplyCannotPermitReplacement() async {
        let client = Client(); client.statusReply = Self.response(active: true); client.disableError = Failure.battery
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "disable"])
    }

    @Test func replacementMustAnswerWithTheNewProtocolBeforeReportingReady() async {
        let client = Client(); client.failVersionAfterRegistration = true
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version", "unregister", "register", "version"])
        #expect(client.calls.filter { $0 == "register" }.count == 1)
    }

    @Test func aStillLoadedOldProtocolIsNotReportedReadyOrRetried() async {
        let client = Client(); client.versionAfterRegistration = 9
        await #expect(throws: HelperClient.HelperError.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version", "unregister", "register", "version"])
        #expect(client.calls.filter { $0 == "register" }.count == 1)
    }

    @Test func pendingApprovalIsReturnedWithoutQueryingAnUnapprovedService() async throws {
        let client = Client(); client.statusAfterRegistration = .requiresApproval
        #expect(try await HelperServiceUpdater(client: client).update() == .requiresApproval)
        #expect(client.calls == ["version", "status", "version", "unregister", "register"])
    }

    @Test func anExpectedApprovalErrorPreservesTheSystemApprovalStep() async throws {
        let client = Client(); client.statusAfterRegistration = .requiresApproval
        client.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: Int(kSMErrorLaunchDeniedByUser))
        #expect(try await HelperServiceUpdater(client: client).update() == .requiresApproval)
        #expect(client.calls.filter { $0 == "register" }.count == 1)
    }

    @Test func aSignatureFailureIsNotHiddenByARequiresApprovalStatus() async {
        let client = Client(); client.statusAfterRegistration = .requiresApproval
        client.registrationError = NSError(domain: "SMAppServiceErrorDomain", code: Int(kSMErrorInvalidSignature))
        do {
            _ = try await HelperServiceUpdater(client: client).update()
            Issue.record("La signature invalide doit être affichée.")
        } catch {
            #expect((error as NSError).code == Int(kSMErrorInvalidSignature))
        }
        #expect(client.calls.filter { $0 == "register" }.count == 1)
    }

    @Test func aRegistrationFailureIsNotReportedReady() async {
        let client = Client(); client.registrationError = Failure.registration
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version", "unregister", "register"])
    }

    @Test func aFailedServiceRemovalNeverRegistersAReplacement() async {
        let client = Client(); client.unregisterError = Failure.unregister
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version", "unregister"])
    }

    @Test func aStillEnabledServiceNeverRegistersAReplacement() async {
        let client = Client(); client.remainEnabledAfterUnregister = true
        await #expect(throws: HelperClient.HelperError.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version", "unregister"])
    }

    @Test func aNewerHelperIsNeverDowngraded() async {
        let client = Client(); client.version = HelperIdentity.protocolVersion + 1
        await #expect(throws: HelperClient.HelperError.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version"])
    }

    @Test(arguments: [4, 5])
    func legacyBatterySelectorsAreRestoredBeforeReplacement(_ version: Int) async throws {
        let client = Client(); client.version = version
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        #expect(client.calls == ["version", "legacyRestore", "version", "unregister", "register", "version"])
        #expect(client.commands.isEmpty)
    }

    @Test func aFailedLegacyRestorationNeverRemovesTheService() async {
        let client = Client(); client.version = 5; client.legacyError = Failure.legacy
        await #expect(throws: Failure.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "legacyRestore"])
    }

    @Test(arguments: [6, 7, 8])
    func previousUUIDSelectorsKeepTheirRestorationPath(_ version: Int) async throws {
        let client = Client(); client.version = version; client.statusReply = Self.response(active: true)
        #expect(try await HelperServiceUpdater(client: client).update() == .ready)
        #expect(client.commands.map(\.0) == [.status, .disable])
        let restoreIndex = try #require(client.calls.firstIndex(of: "disable"))
        let removalIndex = try #require(client.calls.firstIndex(of: "unregister"))
        #expect(restoreIndex < removalIndex)
    }

    @Test func aHelperChangedDuringRestorationIsNotRemoved() async {
        let client = Client(); client.nextVersionBeforeRemoval = HelperIdentity.protocolVersion
        await #expect(throws: HelperClient.HelperError.self) { try await HelperServiceUpdater(client: client).update() }
        #expect(client.calls == ["version", "status", "version"])
    }

    @Test func aRequiresApprovalServiceIsNotReplacedOrQueried() async throws {
        let client = Client(); client.status = .requiresApproval
        #expect(try await HelperServiceUpdater(client: client).update() == .requiresApproval)
        #expect(client.calls.isEmpty)
    }

    @Test func concurrentExplicitActionsCannotDuplicateTheReplacement() async throws {
        let client = Client(); let gate = Gate(); client.versionGate = gate
        let updater = HelperServiceUpdater(client: client)
        let first = Task { try await updater.update() }
        await gate.waitUntilEntered()
        await #expect(throws: HelperClient.HelperError.self) { try await updater.update() }
        await #expect(throws: HelperClient.HelperError.self) { try await updater.unregister() }
        gate.release()
        #expect(try await first.value == .ready)
        #expect(client.calls.filter { $0 == "register" }.count == 1)
    }

    @Test func cancellationBeforeTheActionCannotMutateTheService() async {
        let client = Client(); let updater = HelperServiceUpdater(client: client)
        let action = Task { try await updater.update() }
        action.cancel()
        await #expect(throws: CancellationError.self) { try await action.value }
        #expect(client.calls.isEmpty)
    }

    @Test func explicitDeactivationStillRestoresVersionNineAfterTheProtocolBump() async throws {
        let client = Client(); client.statusReply = Self.response(active: true)
        try await HelperServiceUpdater(client: client).unregister()
        #expect(client.calls == ["version", "status", "disable", "version", "unregister"])
        #expect(!client.calls.contains("register"))
    }
}
