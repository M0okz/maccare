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
        case notEnabled, unavailable(String), incompatible(Int)
        var errorDescription: String? {
            switch self {
            case .notEnabled: return "l’assistant système n’est pas activé"
            case .unavailable(let m): return "assistant indisponible : \(m)"
            case .incompatible(let v): return "assistant d'une autre version (protocole \(v)) : réactivez-le"
            }
        }
    }

    static var service: SMAppService { SMAppService.daemon(plistName: HelperIdentity.daemonPlist) }

    /// `.notRegistered`, `.requiresApproval` (à approuver dans Réglages Système), `.enabled`, ou
    /// `.notFound`. Observé sur macOS : un démon **jamais enregistré** est rapporté `.notFound` alors
    /// que son plist est bien dans le paquet ; `.notFound` ne signifie donc pas à lui seul « app mal
    /// placée ». L'interface distingue ce cas en vérifiant la présence du plist dans le paquet.
    static var status: SMAppService.Status { service.status }

    static func register() throws { try service.register() }
    static func unregister() async throws {
        if status == .enabled {
            let (version, _): (Int, String) = try await call(timeout: 8) { helper, done in helper.version { done(($0, $1)) } }
            if version == 4 || version == 5 {
                try await LegacyBatteryHelper.restoreBeforeUnregister()
            } else if version == 6 || version == 7 {
                // Version 6 has the same UUID-bearing selector. Only stop/verify
                // it; no activation or automatic replacement of a loaded service.
                let json: String = try await call(timeout: 8) { helper, done in
                    helper.battery(command: "status", sessionID: "", configurationJSON: "{}", withReply: done)
                }
                let current = try JSONDecoder().decode(BatteryProtectionStatus.self, from: Data(json.utf8))
                if current.active || current.restoring {
                    let result: String = try await call(timeout: 8) { helper, done in
                        helper.battery(command: "disable", sessionID: UUID().uuidString, configurationJSON: "{}", withReply: done)
                    }
                    let stopped = try JSONDecoder().decode(BatteryProtectionStatus.self, from: Data(result.utf8))
                    guard !stopped.active, !stopped.restoring, stopped.error == nil else {
                        throw HelperError.unavailable(stopped.error ?? "restaurez la charge avant de désactiver l’ancien assistant")
                    }
                }
            } else if version == HelperIdentity.protocolVersion {
                let current = try await battery(.status)
                if current.active || current.restoring {
                    let stopped = try await battery(.disable, sessionID: UUID())
                    guard !stopped.active, !stopped.restoring, stopped.error == nil else {
                        throw HelperError.unavailable(stopped.error ?? "restaurez la charge avant de désactiver l’assistant")
                    }
                }
            } else if version > 3 { throw HelperError.incompatible(version) }
        }
        try await service.unregister()
    }
    static func openApproval() { SMAppService.openSystemSettingsLoginItems() }

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
