import Darwin
import Foundation

/// Demande à macOS de réduire ses instantanés locaux avec tmutil thinlocalsnapshots.
/// Aucune suppression d’instantané APFS par identifiant, aucun volume fourni par le client.
public enum LocalSnapshotMaintenance {
    public static let thinningCommand = MaintenanceCommand(
        "/usr/bin/tmutil", ["thinlocalsnapshots", "/", String(Int64.max), "4"], timeout: 600
    )
    public static let listingCommand = MaintenanceCommand("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 60)

    public static func snapshotCount(in text: String) -> Int {
        text.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("com.apple.TimeMachine.")
        }.count
    }

    public static func physicalFreeBytes() -> UInt64? {
        var stats = statfs()
        guard statfs("/System/Volumes/Data", &stats) == 0 else { return nil }
        return UInt64(stats.f_bavail) * UInt64(stats.f_bsize)
    }

    public static func execute(run: (MaintenanceCommand) -> MaintenanceCommandOutput = MaintenanceCommandRunner.run,
                               freeBytes: () -> UInt64? = physicalFreeBytes) -> MaintenanceReport {
        let before = run(listingCommand)
        guard before.ok else {
            return .init(.failed, "Impossible de lire les instantanés Time Machine locaux. Aucune réduction n’a été lancée.", details: before.text)
        }
        let countBefore = snapshotCount(in: before.text)
        guard countBefore > 0 else {
            return .init(.completed, "Aucun instantané Time Machine local à réduire.", details: "Aucun point de restauration local n’a été retiré par cette étape.")
        }
        let freeBefore = freeBytes()
        let result = run(thinningCommand)
        guard result.ok else {
            // tmutil peut avoir déjà retiré des instantanés avant de signaler une erreur.
            return .init(.partial,
                         result.timedOut ? "La réduction des instantanés a dépassé son délai. Certains points locaux peuvent avoir été retirés."
                         : "macOS n’a pas terminé la réduction des instantanés locaux. Certains points peuvent avoir été retirés.",
                         details: result.text)
        }
        let after = run(listingCommand)
        let freeAfter = freeBytes()
        var details = [result.text]
        if let freeBefore, let freeAfter {
            let increase = freeAfter >= freeBefore ? freeAfter - freeBefore : 0
            details.append("Augmentation de l’espace libre observée : \(increase) octets. Cette mesure peut varier avec les autres activités du Mac.")
        }
        guard after.ok else {
            details.append(after.text)
            return .init(.partial, "Réduction demandée à macOS, mais le contrôle final des instantanés a échoué.", details: details.joined(separator: "\n"))
        }
        let countAfter = snapshotCount(in: after.text)
        details.append("Instantanés locaux recensés : \(countBefore) avant, \(countAfter) après. macOS choisit les points éligibles et la comptabilisation de l’espace peut être différée.")
        return .init(.completed, "macOS a terminé la réduction des instantanés Time Machine locaux.", details: details.joined(separator: "\n"))
    }
}

/// Les deux étapes sont indépendantes et leurs résultats restent distincts dans le compte rendu.
public enum PurgeableMaintenanceReport {
    public static func combine(snapshots: MaintenanceReport?, caches: MaintenanceReport?) -> MaintenanceReport {
        let reports = [snapshots, caches].compactMap { $0 }
        guard !reports.isEmpty else { return .init(.completed, "Aucun cache éligible à libérer. Les instantanés locaux sont exclus dans les réglages.") }
        let successes = reports.filter(\.succeeded).count
        let status: MaintenanceReport.Status = successes == reports.count ? .completed
            : (successes > 0 || reports.contains { $0.status == .partial } ? .partial : .failed)
        return .init(status, reports.map(\.message).joined(separator: "\n"),
                     details: reports.map(\.details).filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }
}
