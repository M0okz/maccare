import Foundation
import CMacCareSMC
import IOKit.pwr_mgt
import MacCareBattery

/// Root controller has its own serial queue and watchdog, independent of long maintenance tasks.
enum BatteryService {
    private static let queue = DispatchQueue(label: "org.maccare.helper.battery")
    private static let store = BatteryRecoveryStore(directory: Audit.directory)
    private static let controller = BatteryProtectionController(hardware: RecoverableChargeHardware(),
        markRecovery: { try store.save($0) }, clearRecovery: { try store.clear() })
    // This value comes from the LOADED launchd job, not from the plist currently on disk.
    // An old registration cannot silently acquire crash-recovery promises after a bundle update.
    private static let recoveryReady = ProcessInfo.processInfo.environment["MACCARE_BATTERY_RECOVERY"] == "1"
    private static var timer: DispatchSourceTimer?
    private static var held = false
    private static var shutdownSignals: [DispatchSourceSignal] = []
    private static var powerPort: IONotificationPortRef?
    private static var notifier: io_object_t = 0
    private static var powerConnection: io_connect_t = 0
    private static var powerReady = false
    private static var recoveryPending = true
    private static var recoveryFailure: String?
    private static var lastAuditError: String?

    static func start() {
        powerConnection = IORegisterForSystemPower(nil, &powerPort, batteryPowerCallback, &notifier)
        if powerConnection != 0, let powerPort, let source = IONotificationPortGetRunLoopSource(powerPort)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerReady = true
        }
        Idle.begin()
        queue.async {
            defer { Idle.end() }
            for number in [SIGTERM, SIGINT] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
                source.setEventHandler {
                    do {
                        if recoveryPending, let record = try store.load() { try controller.recover(record) }
                        try controller.shutdown()
                        exit(0)
                    } catch {
                        audit("shutdown-restore", error: error.localizedDescription)
                        exit(1)
                    }
                }
                shutdownSignals.append(source)
                source.resume()
            }
            poll()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 5, repeating: 5)
            source.setEventHandler { poll() }
            timer = source
            source.resume()
        }
    }

    static func powerEvent(_ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
        let token = Int(bitPattern: argument)
        switch message {
        case UInt32(MCSystemCanSleep): IOAllowPowerChange(powerConnection, token)
        case UInt32(MCSystemWillSleep):
            queue.async {
                do { try controller.prepareForSleep() }
                catch { audit("sleep-restore", error: error.localizedDescription) }
                IOAllowPowerChange(powerConnection, token)
            }
        case UInt32(MCSystemDidWake): queue.async { controller.didWake(now: ProcessInfo.processInfo.systemUptime); poll() }
        default: break
        }
    }

    static func execute(command raw: String, sessionID rawSession: String, configurationJSON: String, uid: uid_t, reply: @escaping (String) -> Void) {
        Idle.begin()
        queue.async {
            defer { Idle.end() }
            if raw == "diagnostics", configurationJSON == "{}", rawSession.isEmpty, uid >= 501 {
                let keys = ["bfF0", "bfD0", "bfE0", "CHTE", "CH0B", "CH0C", "CH0I", "CH0J", "CHIE"]
                var rows: [[String: Any]] = []
                for transport: Int32 in [0, 1] {
                    for handshake: Int32 in [0, 1] {
                        for (index, key) in keys.enumerated() {
                            var field = MCKeyDiagnostic()
                            let code = maccare_key_diagnostic(Int32(index), transport, handshake, &field)
                            let bytes = withUnsafeBytes(of: field.bytes) { $0.map { String(format: "%02x", $0) }.joined() }
                            rows.append(["key": key, "transport": transport, "handshake": handshake, "result": code,
                                         "size": field.size, "type": String(format: "%08x", field.type), "bytes": bytes])
                        }
                    }
                }
                let result: [String: Any] = ["method": "read-only", "helperUID": geteuid(), "smc": rows]
                let data = (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                reply(String(decoding: data, as: UTF8.self)); return
            }
            let snapshot = BatterySnapshot.read()
            var result: BatteryProtectionStatus
            if let command = BatteryCommand(rawValue: raw), raw.utf8.count <= 32, configurationJSON.utf8.count <= 512, rawSession.utf8.count <= 36,
               command == .status || UUID(uuidString: rawSession) != nil,
               command != .enable || recoveryReady,
               !recoveryPending, powerReady || command == .status || command == .disable {
                let config = try? JSONDecoder().decode(BatteryConfiguration.self, from: Data(configurationJSON.utf8))
                result = controller.execute(command, configuration: config, uid: uid, sessionID: UUID(uuidString: rawSession),
                                            snapshot: snapshot, now: ProcessInfo.processInfo.systemUptime)
                if command != .status && command != .heartbeat { audit(command.rawValue, error: result.error, uid: uid) }
            } else {
                result = .init(snapshot: snapshot, error: recoveryPending
                    ? (recoveryFailure ?? "Restauration de la charge en cours ; réessayez après sa réussite.")
                    : (!recoveryReady ? "Réactivez explicitement l’assistant système pour charger sa surveillance de la batterie."
                        : "Commande refusée ou surveillance de la veille indisponible."), restoring: recoveryPending)
            }
            result.recoveryReady = recoveryReady
            keepAlive()
            reply(String(decoding: (try? JSONEncoder().encode(result)) ?? Data(), as: UTF8.self))
        }
    }
    private static func poll() {
        if recoveryPending {
            do {
                if let record = try store.load() { try controller.recover(record); audit("recovery", error: nil) }
                recoveryPending = false; recoveryFailure = nil
            } catch {
                recoveryFailure = error.localizedDescription
                if lastAuditError != recoveryFailure { audit("recovery", error: recoveryFailure); lastAuditError = recoveryFailure }
            }
        } else if controller.requiresWatchdog {
            let status = controller.tick(snapshot: .read(), now: ProcessInfo.processInfo.systemUptime)
            if let error = status.error, lastAuditError != error { audit("watchdog", error: error) }
            lastAuditError = status.error
        }
        keepAlive()
    }
    private static func keepAlive() {
        let needed = controller.requiresWatchdog || recoveryPending
        if needed && !held { held = true; Idle.begin() }
        if !needed && held { held = false; Idle.end() }
    }
    private static func audit(_ operation: String, error: String?, uid: uid_t? = nil) {
        // Audit serialises its file and persists this entry before a signal handler exits.
        Audit.append([
            "date": ISO8601DateFormatter().string(from: Date()), "operation": "battery.\(operation)",
            "error": error as Any? ?? NSNull(), "uid": uid as Any? ?? NSNull(),
        ])
    }
}

private func batteryPowerCallback(_ refcon: UnsafeMutableRawPointer?, _ service: io_service_t,
                                  _ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
    BatteryService.powerEvent(message, argument)
}
