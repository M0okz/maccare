import Foundation
import MacCareMaintenance

enum PerformanceTaskPresentation {
    static func title(_ task: PerformanceTask) -> String {
        switch task {
        case .mail: return "Optimiser Mail"
        case .purgeable: return "Libérer l’espace purgeable"
        case .permissions: return "Autorisations du compte"
        case .spotlight, .dns: return task.title
        }
    }
    static func effect(_ task: PerformanceTask, includeLocalSnapshots: Bool) -> String {
        guard task == .purgeable else { return task.effect }
        if includeLocalSnapshots {
            return "Les caches examinés seront supprimés définitivement. macOS réduira aussi les instantanés Time Machine locaux éligibles : certains points de restauration présents sur ce Mac seront définitivement supprimés. Les sauvegardes sur disque externe ou réseau ne sont pas visées. Le gain dépend de macOS et peut apparaître avec un délai."
        }
        return "Seuls les caches examinés seront supprimés définitivement. Les applications concernées devront les recréer. Les instantanés Time Machine locaux sont exclus dans Réglages → Performances et seront conservés."
    }
    static func unavailable(_ task: PerformanceTask, helperEnabled: Bool, fullDiskGranted: Bool, mailRunning: Bool,
                            preparing: Bool, cacheCount: Int?, cacheError: String?, includeLocalSnapshots: Bool = false) -> String? {
        if task.requiresHelper(includeLocalSnapshots: includeLocalSnapshots) && !helperEnabled { return "L’assistant système est nécessaire pour cette tâche." }
        if task == .mail {
            if !fullDiskGranted { return "L’Accès complet au disque est nécessaire pour examiner les données de Mail." }
            if mailRunning { return "Quittez Mail avant de choisir cette tâche." }
        }
        if task == .purgeable {
            if includeLocalSnapshots { return nil }
            if preparing { return "Examen des caches en cours…" }
            if let cacheError { return cacheError }
            guard let cacheCount else { return "Actualisez les caches avant de choisir cette tâche." }
            if cacheCount == 0 { return "Aucun cache éligible parmi les applications installées et fermées." }
        }
        return nil
    }
}
