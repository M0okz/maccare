import Foundation

/// Liste fermée : aucun chemin, argument ou UID fourni par un message XPC.
public enum PrivilegedMaintenance {
    public static func commands(for task: PerformanceTask, authenticatedUID: UInt32) -> [MaintenanceCommand]? {
        guard authenticatedUID >= 501 && authenticatedUID < UInt32.max else { return nil }
        switch task {
        case .dns:
            return [.init("/usr/bin/dscacheutil", ["-flushcache"]),
                    .init("/usr/bin/killall", ["-HUP", "mDNSResponder"])]
        case .spotlight: return [.init("/usr/bin/mdutil", ["-E", "/"], timeout: 120)]
        case .permissions:
            return [.init("/usr/sbin/diskutil", ["resetUserPermissions", "/", String(authenticatedUID)], timeout: 600)]
        case .purgeable: return [LocalSnapshotMaintenance.thinningCommand]
        case .mail: return nil
        }
    }

    public static func execute(_ task: PerformanceTask, authenticatedUID: UInt32,
                               run: (MaintenanceCommand) -> MaintenanceCommandOutput = MaintenanceCommandRunner.run) -> MaintenanceReport {
        guard let commands = commands(for: task, authenticatedUID: authenticatedUID) else {
            return .init(.failed, "Opération refusée par l’assistant.")
        }
        if task == .purgeable { return LocalSnapshotMaintenance.execute(run: run) }
        if task == .spotlight {
            let state = run(.init("/usr/bin/mdutil", ["-s", "/"]))
            guard state.ok, state.text.contains("Indexing enabled") else {
                return .init(.failed, "Spotlight est désactivé ou son état est illisible. Aucun index n’a été effacé.", details: state.text)
            }
        }
        var logs: [String] = []
        for (index, command) in commands.enumerated() {
            let result = run(command)
            logs.append(result.text)
            guard result.ok else {
                return .init(index == 0 ? .failed : .partial,
                             result.timedOut ? "Le délai maximal est dépassé. Vérifiez l’état du système avant de réessayer."
                             : "La tâche n’a pas abouti (code \(result.status)).",
                             details: logs.joined(separator: "\n"))
            }
        }
        let message: String
        switch task {
        case .spotlight: message = "Réindexation demandée à macOS. Elle se poursuit en arrière-plan."
        case .permissions: message = "macOS a terminé la réinitialisation des autorisations de votre dossier personnel."
        default: message = "Cache DNS vidé et service de résolution rechargé."
        }
        return .init(task == .spotlight ? .started : .completed, message, details: logs.joined(separator: "\n"))
    }
}
