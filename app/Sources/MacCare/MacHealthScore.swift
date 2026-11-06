import Foundation
import MacCareBattery

/// Indice explicable de l’état actuel ; aucune donnée d’activité ne simule une panne.
enum MacHealthScore {
    enum Grade: String { case poor = "Mauvais", good = "Bien", excellent = "Excellent" }
    struct Component: Identifiable {
        let id: String
        let title: String
        let earned: Double
        let weight: Double
        let detail: String
    }
    struct Assessment {
        let percent: Int?
        let components: [Component]
        let notes: [String]
        var grade: Grade? { percent.map { $0 < 50 ? .poor : $0 < 85 ? .good : .excellent } }
    }

    static func assess(free: UInt64?, total: UInt64?, pressure: MemoryPressureLevel?,
                       thermal: ProcessInfo.ThermalState, battery: BatterySnapshot?) -> Assessment {
        guard let free, let total, total > 0, let pressure else {
            return .init(percent: nil, components: [], notes: ["Calcul en cours : espace disponible et pression mémoire nécessaires."])
        }
        let thermalFactor: Double
        switch thermal {
        case .nominal: thermalFactor = 1
        case .fair: thermalFactor = 0.75
        case .serious: thermalFactor = 0.35
        case .critical: thermalFactor = 0
        @unknown default: return .init(percent: nil, components: [], notes: ["État thermique indisponible."])
        }
        let available = Double(min(free, total))
        let reserve = min(Double(total) * 0.15, 50_000_000_000)
        let storageFactor = min(1, max(0, available / reserve))
        let memoryFactor: Double = pressure == .normal ? 1 : pressure == .warning ? 0.6 : 0.1
        var components = [
            Component(id: "storage", title: "Stockage", earned: 30 * storageFactor, weight: 30,
                      detail: "Réserve visée : 15 % du volume, plafonnée à 50 Go."),
            Component(id: "memory", title: "Pression mémoire", earned: 30 * memoryFactor, weight: 30, detail: pressure.title),
            Component(id: "thermal", title: "État thermique", earned: 25 * thermalFactor, weight: 25,
                      detail: thermal == .nominal ? "Normal" : thermal == .fair ? "Modéré" : thermal == .serious ? "Élevé" : "Critique")
        ]
        var ceiling = 100
        var notes: [String] = []
        if available / Double(total) < 0.02 && available < 5_000_000_000 {
            ceiling = min(ceiling, 45); notes.append("Espace disponible critique : indice plafonné à 45 %.")
        }
        if pressure == .critical { ceiling = min(ceiling, 40); notes.append("Pression mémoire critique : indice plafonné à 40 %.") }
        if thermal == .serious { ceiling = min(ceiling, 49); notes.append("État thermique élevé : indice plafonné à 49 %.") }
        if thermal == .critical { ceiling = min(ceiling, 25); notes.append("État thermique critique : indice plafonné à 25 %.") }
        if let battery, battery.present {
            if battery.batteryFault {
                components.append(.init(id: "battery", title: "Batterie", earned: 0, weight: 15, detail: "Défaut signalé par macOS"))
                ceiling = min(ceiling, 35); notes.append("Défaut batterie signalé : indice plafonné à 35 %.")
            } else if let capacity = battery.healthPercent, (0...100).contains(capacity) {
                components.append(.init(id: "battery", title: "Batterie", earned: 15 * Double(capacity) / 100, weight: 15,
                                        detail: "Capacité restante estimée : \(capacity) %"))
                if capacity < 60 {
                    ceiling = min(ceiling, 49); notes.append("Capacité batterie très réduite : indice plafonné à 49 %.")
                } else if capacity < 80 {
                    ceiling = min(ceiling, 84); notes.append("Capacité batterie réduite : indice plafonné à 84 %.")
                }
            } else {
                ceiling = min(ceiling, 84); notes.append("Capacité batterie indisponible : indice partiel, plafonné à 84 %.")
            }
            if ["Poor", "Check Battery", "Permanent Battery Failure"].contains(battery.healthState ?? "") {
                ceiling = min(ceiling, 49); notes.append("État de la batterie à vérifier selon macOS : indice plafonné à 49 %.")
            }
        } else if battery == nil {
            ceiling = min(ceiling, 84); notes.append("Lecture de la batterie en attente : indice partiel, plafonné à 84 %.")
        }
        let weight = components.reduce(0) { $0 + $1.weight }
        let earned = components.reduce(0) { $0 + $1.earned }
        return .init(percent: min(ceiling, max(0, Int((earned / weight * 100).rounded()))), components: components, notes: notes)
    }
}
