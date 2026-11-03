import Foundation

/// Les trois portes d’entrée du gestionnaire Performances.
enum PerformanceCategory: String, CaseIterable, Identifiable {
    case maintenance, login, background
    var id: String { rawValue }
    var title: String {
        switch self {
        case .maintenance: return "Tâches d’entretien"
        case .login: return "Éléments d’ouverture"
        case .background: return "Éléments d’arrière-plan"
        }
    }
    var symbol: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver"
        case .login: return "power"
        case .background: return "gearshape.2"
        }
    }
    var detail: String {
        switch self {
        case .maintenance: return "Entretenez Mail, les caches, Spotlight, les autorisations et le DNS."
        case .login: return "Examinez les applications qui s’ouvrent à la connexion et accédez aux réglages macOS."
        case .background: return "Examinez les agents de lancement de votre session et du système."
        }
    }
}
