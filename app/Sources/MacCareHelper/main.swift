import CMacCareCore
import Foundation
import Darwin
import MacCareBattery
import MacCareMaintenance
import MacCareHelperProtocol

// Assistant privilégié de MacCare (lot 7). Démon lancé par launchd en `root`, à la demande, et
// enregistré par l'app via SMAppService.daemon. Il fait son travail puis **se termine** après un
// court repos (voir `Idle`) : il ne reste pas résident en root. Il n'expose que le protocole `MacCareHelperXPC` et n'exécute que
// les règles système fermées du moteur et le catalogue de maintenance compilé : jamais un chemin, une commande ou un script fourni par
// l'appelant. Voir `docs/architecture.md`.

/// Journal d'audit en ajout seul, lisible par `root` uniquement. L'app n'en reçoit qu'une
/// synthèse sans chemins (`journal(since:)`).
enum Audit {
    static let directory = URL(fileURLWithPath: "/Library/Application Support/MacCare Helper", isDirectory: true)
    static let file = directory.appendingPathComponent("audit.jsonl")
    static let maxBytes = 1_000_000

    private static let lock = NSLock()
    static func append(_ entry: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Rotation simple : au-delà du plafond, l'ancien journal devient .1 (écrasé ensuite).
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxBytes {
            let old = directory.appendingPathComponent("audit.1.jsonl")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: file, to: old)
        }
        guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        if !fm.fileExists(atPath: file.path) {
            fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        }
    }

    /// Entrées depuis `since`, sans les chemins (seulement règle, opération, comptes, raisons).
    static func summary(since: Date) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        return text.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = (obj["date"] as? String).flatMap(iso.date(from:)), d >= since else { return nil }
            return obj.filter { ["date", "rule", "operation", "removed", "freed_bytes", "refused", "error", "status", "uid"].contains($0.key) }
        }
    }
}

/// Appel du moteur Rust (chaîne JSON en entrée et en sortie).
func engine(_ fn: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?, _ input: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: input),
          let json = String(data: data, encoding: .utf8) else { return #"{"error":"entrée invalide"}"# }
    guard let out = json.withCString({ fn($0) }) else { return #"{"error":"moteur indisponible"}"# }
    defer { maccare_string_free(out) }
    return String(cString: out)
}

func decode(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
}

/// Arrêt au repos : sans connexion ouverte ni opération en cours pendant `delay`, le démon se
/// termine ; launchd le relancera au prochain message (service Mach à la demande).
enum Idle {
    static let delay: TimeInterval = 30
    private static let lock = NSLock()
    private static var connections = 0
    private static var operations = 0
    private static var lastActivity = Date()

    static func connectionOpened() { update { connections += 1 } }
    static func connectionClosed() { update { connections -= 1 } }
    static func begin() { update { operations += 1 } }
    static func end() { update { operations -= 1 } }

    private static func update(_ change: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        change()
        lastActivity = Date()
    }

    /// Vérifie périodiquement ; termine le processus si tout est au repos depuis `delay`.
    static func watch() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            lock.lock()
            let quiet = connections <= 0 && operations <= 0 && Date().timeIntervalSince(lastActivity) >= delay
            lock.unlock()
            if quiet { exit(0) }
        }
    }
}

final class HelperService: NSObject, MacCareHelperXPC {
    private let authenticatedUID: uid_t
    init(authenticatedUID: uid_t) { self.authenticatedUID = authenticatedUID }
    /// Une opération à la fois ; et au moins une seconde entre deux suppressions (un appelant
    /// qui boucle est ralenti).
    private static let queue = DispatchQueue(label: "org.maccare.helper.operations")
    private static var lastRemoval = Date.distantPast
    private static let maxIdentities = 10_000

    func battery(command: String, sessionID: String, configurationJSON: String, withReply reply: @escaping (String) -> Void) {
        BatteryService.execute(command: command, sessionID: sessionID, configurationJSON: configurationJSON, uid: authenticatedUID, reply: reply)
    }

    func version(withReply reply: @escaping (Int, String) -> Void) {
        reply(HelperIdentity.protocolVersion, String(cString: maccare_version()))
    }

    func list(rule: String, withReply reply: @escaping (String) -> Void) {
        // Lecture seule : pas inscrite au journal d'audit, réservé à ce qui modifie le disque.
        Idle.begin()
        Self.queue.async {
            defer { Idle.end() }
            reply(engine(maccare_system_list, ["rule": rule]))
        }
    }

    func remove(rule: String, identitiesJSON: String, withReply reply: @escaping (String) -> Void) {
        Idle.begin()
        Self.queue.async {
            defer { Idle.end() }
            // Seule forme admise : un tableau d'identités numériques, borné.
            guard let raw = try? JSONSerialization.jsonObject(with: Data(identitiesJSON.utf8)) as? [[String: Any]],
                  raw.count <= Self.maxIdentities else {
                reply(#"{"error":"identités invalides"}"#)
                return
            }
            let ids: [[String: UInt64]] = raw.compactMap { d in
                guard let dev = (d["device"] as? NSNumber)?.uint64Value, let ino = (d["inode"] as? NSNumber)?.uint64Value else { return nil }
                return ["device": dev, "inode": ino]
            }
            guard ids.count == raw.count else {
                reply(#"{"error":"identités invalides"}"#)
                return
            }
            let wait = 1 - Date().timeIntervalSince(Self.lastRemoval)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            Self.lastRemoval = Date()

            let result = engine(maccare_system_remove, ["rule": rule, "identities": ids])
            let obj = decode(result)
            let refused = (obj["refused"] as? [[Any]]) ?? []
            Audit.append([
                "date": ISO8601DateFormatter().string(from: Date()), "rule": rule, "operation": "remove",
                "requested": ids.count, "removed": obj["removed"] ?? 0, "freed_bytes": obj["freed_bytes"] ?? 0,
                // Raisons agrégées pour la synthèse ; chemins refusés gardés dans le journal root seul.
                "refused": refused.compactMap { $0.last as? String },
                "refused_paths": refused.compactMap { $0.first as? String },
                "error": obj["error"] ?? NSNull(),
            ])
            reply(result)
        }
    }

    func maintenance(task rawTask: String, withReply reply: @escaping (String) -> Void) {
        guard rawTask.utf8.count <= 32 else {
            reply(#"{"status":"failed","message":"Tâche invalide.","details":""}"#)
            return
        }
        Idle.begin()
        Self.queue.async { [authenticatedUID] in
            defer { Idle.end() }
            let result: MaintenanceReport
            if let task = PerformanceTask(rawValue: rawTask), task.requiresHelper,
               authenticatedUID >= 501, let account = getpwuid(authenticatedUID),
               let homePointer = account.pointee.pw_dir {
                let home = URL(fileURLWithPath: String(cString: homePointer))
                // Refuse les comptes de service, distants et les dossiers redirigés.
                if home.deletingLastPathComponent().path == "/Users",
                   home.resolvingSymlinksInPath().path == home.path {
                    result = PrivilegedMaintenance.execute(task, authenticatedUID: authenticatedUID)
                } else {
                    result = .init(.failed, "Compte local ou dossier personnel non pris en charge.")
                }
            } else {
                result = .init(.failed, "Tâche ou identité refusée par l’assistant.")
            }
            Audit.append([
                "date": ISO8601DateFormatter().string(from: Date()), "operation": "maintenance",
                "rule": rawTask, "uid": authenticatedUID, "status": result.status.rawValue,
                "error": result.succeeded ? NSNull() : result.message as Any,
            ])
            let data = (try? JSONEncoder().encode(result)) ?? Data()
            reply(String(decoding: data, as: UTF8.self))
        }
    }

    func journal(since: Date, withReply reply: @escaping (String) -> Void) {
        Idle.begin()
        Self.queue.async {
            defer { Idle.end() }
            let entries = Audit.summary(since: since)
            let data = (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8)
            reply(String(decoding: data, as: UTF8.self))
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Exigence de signature vérifiée par la connexion à CHAQUE message (macOS 13+),
        // jamais un contrôle fondé sur le PID.
        connection.setCodeSigningRequirement(HelperIdentity.appRequirement)
        connection.exportedInterface = NSXPCInterface(with: MacCareHelperXPC.self)
        connection.exportedObject = HelperService(authenticatedUID: connection.effectiveUserIdentifier)
        Idle.connectionOpened()
        connection.invalidationHandler = { Idle.connectionClosed() }
        connection.resume()
        return true
    }
}

// Explicit read-only diagnostic: never starts the daemon or writes SMC state.
if CommandLine.arguments.contains("--battery-diagnostics") {
    let snapshot = BatterySnapshot.read()
    let hardware = AppleSiliconChargeHardware()
    var value: UInt8?
    var diagnosticError: String?
    do { value = try hardware.readSwitch() } catch { diagnosticError = error.localizedDescription }
    let result = BatteryProtectionStatus(snapshot: snapshot, firmwareManaged: hardware.firmwareManaged, supported: value != nil,
        suspended: value == 2, message: "Diagnostic en lecture seule",
        error: diagnosticError)
    if let data = try? JSONEncoder().encode(result) { print(String(decoding: data, as: UTF8.self)) }
    exit(0)
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.machService)
listener.delegate = delegate
listener.resume()
BatteryService.start()
Idle.watch()
RunLoop.main.run()
