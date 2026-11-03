import Foundation
import MacCareBattery

enum HomeBatteryPresentation {
    static func charge(_ snapshot: BatterySnapshot?) -> String {
        guard let snapshot, snapshot.present, let value = snapshot.percent, (0...100).contains(value) else { return "—" }
        return "\(value) %"
    }
    static func source(_ snapshot: BatterySnapshot?) -> String {
        guard let snapshot else { return "Lecture de la batterie…" }
        guard snapshot.present else { return "Aucune batterie intégrée" }
        guard snapshot.powerStateKnown else { return "Alimentation indisponible" }
        return snapshot.onAC ? (snapshot.charging ? "Branché · en charge" : "Branché · charge en pause") : "Sur batterie"
    }
    static func condition(_ snapshot: BatterySnapshot?) -> String {
        guard let snapshot, snapshot.present else { return "—" }
        if snapshot.batteryFault { return "À vérifier" }
        switch snapshot.healthState {
        case "Good": return "Normal"
        case "Fair": return "Capacité réduite"
        case "Poor", "Check Battery", "Permanent Battery Failure": return "À vérifier"
        default: return "Indisponible"
        }
    }
    static func remaining(_ snapshot: BatterySnapshot?) -> String? {
        guard let snapshot, snapshot.present, snapshot.powerStateKnown, !snapshot.onAC, !snapshot.charging,
              let minutes = snapshot.minutesRemaining, minutes > 0 else { return nil }
        let hours = minutes / 60, remainder = minutes % 60
        let duration = hours > 0 ? "\(hours) h" + (remainder > 0 ? " \(remainder) min" : "") : "\(minutes) min"
        return "Environ \(duration) restantes"
    }
}
