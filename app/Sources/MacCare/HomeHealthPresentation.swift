import Foundation
import MacCareBattery

/// Résumé lisible des mesures existantes, distinct du score détaillé du volet.
struct HomeHealthPresentation {
    enum State: Equatable { case healthy, watch, check, reading, partial }
    let assessment: MacHealthScore.Assessment
    let state: State
    let detail: String

    var title: String {
        switch state {
        case .healthy: return "Tout va bien"
        case .watch: return "À surveiller"
        case .check: return "À vérifier"
        case .reading: return "Lecture en cours"
        case .partial: return "Mesures partielles"
        }
    }

    init(storage: TrayStorageUsage?, pressure: MemoryPressureLevel?, thermal: ProcessInfo.ThermalState,
         battery: BatterySnapshot?) {
        assessment = MacHealthScore.assess(free: storage?.available, total: storage?.total,
                                           pressure: pressure, thermal: thermal, battery: battery)
        if thermal == .critical || thermal == .serious {
            state = .check; detail = "État thermique élevé"
        } else if battery?.present == true && battery?.batteryFault == true {
            state = .check; detail = "Batterie à vérifier"
        } else if pressure == .critical {
            state = .check; detail = "Pression mémoire critique"
        } else if let storage, storage.available < 5_000_000_000 && storage.fraction > 0.98 {
            state = .check; detail = "Espace disponible critique"
        } else if assessment.grade == .poor {
            state = .check
            let batteryIssue = battery?.present == true &&
                (battery?.healthPercent.map { (0..<60).contains($0) } == true ||
                 ["Poor", "Check Battery", "Permanent Battery Failure"].contains(battery?.healthState ?? ""))
            detail = batteryIssue ? "État de la batterie à vérifier" : "Plusieurs indicateurs à vérifier"
        } else if let storage, StorageAlertPolicy.isLow(free: storage.available, total: storage.total) {
            state = .watch; detail = "Stockage presque plein"
        } else if pressure == .warning {
            state = .watch; detail = "Pression mémoire élevée"
        } else if thermal == .fair {
            state = .watch; detail = "État thermique modéré"
        } else if battery?.present == true, let capacity = battery?.healthPercent, (0..<80).contains(capacity) {
            state = capacity < 60 ? .check : .watch; detail = "Capacité de la batterie réduite"
        } else if assessment.grade == nil {
            state = .reading; detail = "En attente des mesures système"
        } else if !assessment.notes.isEmpty {
            state = .partial
            detail = battery == nil ? "Lecture de la batterie en attente" : "État de santé de la batterie indisponible"
        } else {
            state = .healthy; detail = "Rien à signaler"
        }
    }
}
