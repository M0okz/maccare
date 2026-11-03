import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, analysis, performance, filesStorage, automation, menu, protection, exclusions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "Général"
        case .performance: return "Performances"
        case .analysis: return "Analyse"
        case .filesStorage: return "Fichiers et disque"
        case .automation: return "Planification"
        case .menu: return "Menu"
        case .protection: return "Suppression"
        case .exclusions: return "Exclusions"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .performance: return "bolt"
        case .analysis: return "sparkle.magnifyingglass"
        case .filesStorage: return "folder"
        case .automation: return "calendar"
        case .menu: return "menubar.rectangle"
        case .protection: return "hand.raised"
        case .exclusions: return "nosign"
        }
    }
}

extension SettingsTab {
    var heading: String { self == .analysis ? "Personnalisez vos analyses" : title }
    var detail: String {
        switch self {
        case .general: return "Gérez les accès de MacCare et son ouverture à la connexion."
        case .performance: return "Choisissez ce qui peut être libéré pendant l’entretien du Mac."
        case .analysis: return "Choisissez le profil et les catégories examinées lors du Smart Scan."
        case .filesStorage: return "Adaptez la recherche de fichiers et l’exploration de vos disques."
        case .automation: return "Gardez un bilan régulier, sans lancer de nettoyage automatique."
        case .menu: return "Retrouvez votre dernier bilan et vos analyses depuis la barre des menus."
        case .protection: return "Choisissez comment les éléments sont supprimés et gérez le nettoyage système."
        case .exclusions: return "Gardez certains fichiers et dossiers à l’écart du nettoyage par règles."
        }
    }
}
