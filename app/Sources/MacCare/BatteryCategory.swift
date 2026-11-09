import SwiftUI

enum BatteryCategory: String, CaseIterable, Identifiable {
    case protection, profiles, discharge, schedules, history, devices

    var id: String { rawValue }
    var title: String {
        switch self {
        case .protection: return "Protection de la batterie"
        case .profiles: return "Profils d’utilisation"
        case .discharge: return "Décharge contrôlée"
        case .schedules: return "Programmations"
        case .history: return "Historique"
        case .devices: return "Appareils Apple"
        }
    }
    var subtitle: String {
        switch self {
        case .protection: return "Réglez la limite de charge et les protections adaptées à votre Mac."
        case .profiles: return "Retrouvez vos réglages pour le bureau, les déplacements et vos habitudes."
        case .discharge: return "Faites redescendre la batterie vers votre limite tout en restant branché."
        case .schedules: return "Prévoyez une recharge ou un changement de limite à l’heure de votre choix."
        case .history: return "Consultez l’évolution de la charge et les derniers relevés de santé."
        case .devices: return "Suivez vos appareils et configurez l’accès à votre iPhone ou iPad en Wi-Fi."
        }
    }
    var symbol: String {
        switch self {
        case .protection: return "checkmark.shield.fill"
        case .profiles: return "slider.horizontal.3"
        case .discharge: return "battery.25percent"
        case .schedules: return "calendar.badge.clock"
        case .history: return "chart.xyaxis.line"
        case .devices: return "iphone"
        }
    }
    var action: String {
        switch self {
        case .protection: return "Gérer la protection"
        case .profiles: return "Choisir un profil"
        case .discharge: return "Voir les options"
        case .schedules: return "Gérer les horaires"
        case .history: return "Consulter les mesures"
        case .devices: return "Voir mes appareils"
        }
    }
}
