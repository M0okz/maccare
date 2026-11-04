import Foundation
import MacCareBattery
import MacCareMaintenance
import MacCareHelperProtocol
import ServiceManagement

/// Client de l'assistant privilégié (nettoyage système, lot 7).
///
/// L'état d'activation est **toujours** lu auprès de macOS (`SMAppService.daemon(...).status`),
/// jamais mémorisé par l'app. La connexion impose au démon l'exigence de signature de
/// l'assistant : on ne parle qu'au vrai `MacCareHelper` de notre équipe.
enum HelperClient {
    enum HelperError: Error, LocalizedError {
        case notEnabled, unavailable(String), incompatible(Int), temporaryLocation
        var errorDescription: String? {
            switch self {
            case .temporaryLocation: return AppInstallLocation.instruction
            case .notEnabled: return "l’assistant système n’est pas activé"
            case .unavailable(let m): return "assistant indisponible : \(m)"
            case .incompatible(let v):
                if v > HelperIdentity.protocolVersion {
                    return "l’assistant utilise un protocole plus récent (\(v)) : mettez MacCare à jour"
                }
                return "l’assistant doit être mis à jour (protocole \(v), attendu \(HelperIdentity.protocolVersion))"
            }
        }
    }

    static var service: SMAppService { SMAppService.daemon(plistName: HelperIdentity.daemonPlist) }

    /// `.notRegistered`, `.requiresApproval` (à approuver dans Réglages Système), `.enabled`, ou
    /// `.notFound`. Observé sur macOS : un démon **jamais enregistré** est rapporté `.notFound` alors
    /// que son plist est bien dans le paquet ; `.notFound` ne signifie donc pas à lui seul « app mal
    /// placée ». L'interface distingue ce cas en vérifiant la présence du plist dans le paquet.
    static var status: SMAppService.Status { service.status }

    static func register() throws {
        guard !AppInstallLocation.isTemporary else { throw HelperError.temporaryLocation }
        try service.register()
    }
    @MainActor private static let serviceUpdater = HelperServiceUpdater(client: SystemHelperServiceLifecycle())

    /// Reads the loaded helper identity without restoring or replacing it.
    @MainActor static func loadedProtocolVersion() async throws -> Int {
        try await serviceUpdater.loadedProtocolVersion()
    }

    /// Performs one explicitly requested replacement, without activating protection.
    @MainActor static func update() async throws -> HelperUpdateResult {
        try await serviceUpdater.update()
    }

    /// Restores the old helper's charge state before explicitly removing its service.
    @MainActor
    static func unregister() async throws {
        try await serviceUpdater.unregister()
    }
    static func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    /// This bypasses only the current-version guard for the closed restoration
    /// commands whose UUID-bearing selector is shared by helper protocols 6–10.
    fileprivate static func restorationReply(_ command: BatteryCommand, sessionID: UUID?) async throws -> String {
        guard command == .status || command == .disable else { throw HelperError.unavailable("commande de restauration invalide") }
        return try await call(timeout: 8) { helper, done in
            helper.battery(command: command.rawValue, sessionID: sessionID?.uuidString ?? "", configurationJSON: "{}", withReply: done)
        }
    }

    fileprivate static func queryLoadedProtocolVersion() async throws -> Int {
        let (version, _): (Int, String) = try await call(timeout: 8) { helper, done in helper.version { done(($0, $1)) } }
        return version
    }

    private static func connection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: MacCareHelperXPC.self)
        c.setCodeSigningRequirement(HelperIdentity.helperRequirement)
        c.resume()
        return c
    }

    /// Appelle l'assistant et attend sa réponse (connexion ouverte puis fermée à chaque appel).
    private static func call<T>(timeout: TimeInterval? = nil, _ body: @escaping (MacCareHelperXPC, @escaping (T) -> Void) -> Void) async throws -> T {
        guard status == .enabled else { throw HelperError.notEnabled }
        let c = connection()
        defer { c.invalidate() }
        return try await withCheckedThrowingContinuation { cont in
            let once = OnceFlag()
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if once.take() { cont.resume(throwing: HelperError.unavailable("délai de réponse dépassé")) }
                }
            }
            let proxy = c.remoteObjectProxyWithErrorHandler { error in
                if once.take() { cont.resume(throwing: HelperError.unavailable(error.localizedDescription)) }
            }
            guard let helper = proxy as? MacCareHelperXPC else {
                if once.take() { cont.resume(throwing: HelperError.unavailable("interface")) }
                return
            }
            body(helper) { value in
                if once.take() { cont.resume(returning: value) }
            }
        }
    }

    /// Vérifie que l'assistant installé parle notre version de protocole.
    static func checkVersion() async throws {
        let (proto, _): (Int, String) = try await call { h, done in h.version { done(($0, $1)) } }
        if proto != HelperIdentity.protocolVersion { throw HelperError.incompatible(proto) }
    }

    /// JSON du moteur : `{"items":[...],"skipped":[...],"truncated"}`.
    static func list(rule: String) async throws -> String {
        try await checkVersion()
        return try await call { h, done in h.list(rule: rule, withReply: done) }
    }

    /// Supprime **définitivement** les éléments désignés (après confirmation dans l'app).
    static func remove(rule: String, identities: [FileIdentity]) async throws -> String {
        try await checkVersion()
        let json = String(decoding: try JSONEncoder().encode(identities), as: UTF8.self)
        return try await call { h, done in h.remove(rule: rule, identitiesJSON: json, withReply: done) }
    }

    static func maintenance(_ task: PerformanceTask) async throws -> MaintenanceReport {
        guard task.requiresHelper else { throw HelperError.unavailable("tâche non privilégiée") }
        try await checkVersion()
        let json: String = try await call { helper, done in
            helper.maintenance(task: task.rawValue, withReply: done)
        }
        return try JSONDecoder().decode(MaintenanceReport.self, from: Data(json.utf8))
    }

    static func batteryHardwareDiagnostics() async throws -> String {
        let (version, _): (Int, String) = try await call(timeout: 8) { helper, done in helper.version { done(($0, $1)) } }
        guard version == HelperIdentity.protocolVersion else { throw HelperError.incompatible(version) }
        return try await call(timeout: 8) { helper, done in
            helper.battery(command: "diagnostics", sessionID: "", configurationJSON: "{}", withReply: done)
        }
    }

    static func prepareBatteryProtection() async throws {
        guard status == .enabled else { throw HelperError.notEnabled }
        let current = try await battery(.status)
        guard current.recoveryReady else {
            throw HelperError.unavailable("réactivez explicitement l’assistant système pour mettre à jour sa surveillance de la batterie")
        }
        // Never stop/re-register the shared helper automatically during activation:
        // it may be performing a disk maintenance operation for another feature.
    }

    static func battery(_ command: BatteryCommand, configuration: BatteryConfiguration? = nil, sessionID: UUID? = nil) async throws -> BatteryProtectionStatus {
        let (proto, _): (Int, String) = try await call(timeout: 8) { h, done in h.version { done(($0, $1)) } }
        guard proto == HelperIdentity.protocolVersion else { throw HelperError.incompatible(proto) }
        let json = configuration.flatMap { try? JSONEncoder().encode($0) } ?? Data("{}".utf8)
        let result: String = try await call(timeout: 8) { helper, done in
            helper.battery(command: command.rawValue, sessionID: sessionID?.uuidString ?? "", configurationJSON: String(decoding: json, as: UTF8.self), withReply: done)
        }
        return try JSONDecoder().decode(BatteryProtectionStatus.self, from: Data(result.utf8))
    }

    /// Synthèse du journal (sans chemins).
    static func journal(since: Date) async throws -> String {
        try await call { h, done in h.journal(since: since, withReply: done) }
    }
}

/// The registration result; `.ready` confirms the current protocol, not an active battery session.
enum HelperUpdateResult: Equatable, Sendable {
    case ready
    case requiresApproval
}

/// The service and closed battery operations needed by an explicit helper replacement.
@MainActor
protocol HelperServiceLifecycle {
    var status: SMAppService.Status { get }
    func loadedProtocolVersion() async throws -> Int
    func restorationReply(_ command: BatteryCommand, sessionID: UUID?) async throws -> String
    func restoreLegacyBattery() async throws
    func unregister() async throws
    func register() throws
}

/// Serializes explicit lifecycle actions while keeping identity checks read-only.
@MainActor
final class HelperServiceUpdater {
    private let client: any HelperServiceLifecycle
    private var mutationInProgress = false

    /// Creates a lifecycle coordinator with a service transport.
    init(client: any HelperServiceLifecycle) { self.client = client }

    /// Reads the loaded protocol without registering, removing, or stopping the service.
    func loadedProtocolVersion() async throws -> Int {
        guard client.status == .enabled else { throw HelperClient.HelperError.notEnabled }
        return try await client.loadedProtocolVersion()
    }

    /// Restores and replaces an older helper once; the caller handles any required approval.
    func update() async throws -> HelperUpdateResult {
        try beginMutation()
        defer { mutationInProgress = false }
        try Task.checkCancellation()
        if client.status == .requiresApproval { return .requiresApproval }
        let version = try await loadedProtocolVersion()
        if version == HelperIdentity.protocolVersion { return .ready }
        try validateRestorableVersion(version)
        try Task.checkCancellation()
        try await restoreBattery(version: version)
        if client.status == .requiresApproval { return .requiresApproval }
        let confirmedVersion = try await loadedProtocolVersion()
        guard confirmedVersion == version else {
            throw HelperClient.HelperError.unavailable("l’assistant a changé pendant la préparation ; actualisez son état")
        }
        try Task.checkCancellation()
        try await client.unregister()
        guard client.status != .enabled else {
            throw HelperClient.HelperError.unavailable("l’arrêt de l’ancien assistant n’est pas confirmé ; vérifiez son état dans Réglages Système")
        }
        // Finish the requested registration after a successful removal, even if
        // the initiating view disappears. No detached task, sleep, or retry loop.
        do { try client.register() }
        catch {
            guard registrationNeedsApproval(error) else { throw error }
            return .requiresApproval
        }
        if client.status == .requiresApproval { return .requiresApproval }
        guard client.status == .enabled else {
            throw HelperClient.HelperError.unavailable("l’activation du nouvel assistant n’est pas confirmée ; vérifiez son état dans Réglages Système")
        }
        let replacementVersion = try await loadedProtocolVersion()
        guard replacementVersion == HelperIdentity.protocolVersion else {
            throw HelperClient.HelperError.incompatible(replacementVersion)
        }
        return .ready
    }

    /// Restores an enabled helper before a user-requested service deactivation.
    func unregister() async throws {
        try beginMutation()
        defer { mutationInProgress = false }
        try Task.checkCancellation()
        if client.status == .enabled {
            let version = try await loadedProtocolVersion()
            try validateRestorableVersion(version)
            try await restoreBattery(version: version)
            guard try await loadedProtocolVersion() == version else {
                throw HelperClient.HelperError.unavailable("l’assistant a changé pendant la préparation ; actualisez son état")
            }
        }
        try Task.checkCancellation()
        try await client.unregister()
    }

    private func beginMutation() throws {
        guard !mutationInProgress else {
            throw HelperClient.HelperError.unavailable("une modification de l’assistant est déjà en cours")
        }
        mutationInProgress = true
    }

    private func validateRestorableVersion(_ version: Int) throws {
        guard (1...HelperIdentity.protocolVersion).contains(version) else {
            throw HelperClient.HelperError.incompatible(version)
        }
    }

    private func restoreBattery(version: Int) async throws {
        if version == 4 || version == 5 {
            try await client.restoreLegacyBattery()
        } else if version >= 6 {
            // Decode only the stable restoration fields, not a newer client's
            // capability enum or recovery journal. Never enable an old helper.
            let current = try decodeRestorationState(await client.restorationReply(.status, sessionID: nil))
            try Task.checkCancellation()
            if current.active || current.restoring || current.error != nil {
                let stopped = try decodeRestorationState(await client.restorationReply(.disable, sessionID: UUID()))
                guard !stopped.active, !stopped.restoring, stopped.error == nil else {
                    throw HelperClient.HelperError.unavailable(stopped.error ?? "l’assistant n’a pas confirmé la restauration de la charge")
                }
            }
        }
    }

    private func decodeRestorationState(_ reply: String) throws -> RestorationState {
        try JSONDecoder().decode(RestorationState.self, from: Data(reply.utf8))
    }

    private func registrationNeedsApproval(_ error: any Error) -> Bool {
        let failure = error as NSError
        let serviceError = failure.domain == "SMAppServiceErrorDomain" || failure.domain == kSMErrorDomainFramework as String
        let approvalError = failure.code == Int(kSMErrorLaunchDeniedByUser) ||
            failure.code == Int(kSMErrorAlreadyRegistered) ||
            (failure.domain == "SMAppServiceErrorDomain" && failure.code == 1)
        return client.status == .requiresApproval && serviceError && approvalError
    }

    private struct RestorationState: Decodable {
        let active: Bool
        let restoring: Bool
        let error: String?
    }
}

@MainActor
private struct SystemHelperServiceLifecycle: HelperServiceLifecycle {
    var status: SMAppService.Status { HelperClient.status }
    func loadedProtocolVersion() async throws -> Int { try await HelperClient.queryLoadedProtocolVersion() }
    func restorationReply(_ command: BatteryCommand, sessionID: UUID?) async throws -> String {
        try await HelperClient.restorationReply(command, sessionID: sessionID)
    }
    func restoreLegacyBattery() async throws { try await LegacyBatteryHelper.restoreBeforeUnregister() }
    func unregister() async throws { try await HelperClient.service.unregister() }
    func register() throws { try HelperClient.register() }
}

/// Garantit qu'une continuation n'est reprise qu'une fois (réponse ou erreur, pas les deux).
private final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
