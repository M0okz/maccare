import Foundation
import Combine

enum CleaningProfile: String, CaseIterable, Identifiable {
    case recommended, thorough, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recommended: return "Recommandé"
        case .thorough: return "Approfondi"
        case .custom: return "Personnalisé"
        }
    }
    var detail: String {
        switch self {
        case .recommended: return "Analyse les catégories à faible risque. Les caches seront recréés à l’usage."
        case .thorough: return "Ajoute les catégories à examiner : sauvegardes, téléchargements et préférences. Elles restent décochées dans les résultats."
        case .custom: return "Analyse uniquement les catégories que vous avez choisies ci-dessous."
        }
    }
}

/// Le profil définit un périmètre d'analyse, jamais une autorisation de suppression.
/// Les IDs sont persistés plutôt que les titres ; un choix vide reste un choix vide.
final class ScanPreferences: ObservableObject {
    private enum Key {
        static let profile = "cleaningProfile"
        static let custom = "cleaningCustomCategories"
    }
    private let defaults: UserDefaults
    @Published private(set) var profile: CleaningProfile
    @Published private(set) var customIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profile = CleaningProfile(rawValue: defaults.string(forKey: Key.profile) ?? "") ?? .recommended
        customIDs = Set(defaults.stringArray(forKey: Key.custom) ?? [])
    }

    func categories(from available: [CleaningCategory]) -> [CleaningCategory] {
        switch profile {
        case .recommended: return available.filter { $0.risk == .safe }
        case .thorough: return available
        case .custom: return available.filter { customIDs.contains($0.id) }
        }
    }

    func select(_ profile: CleaningProfile) {
        self.profile = profile
        defaults.set(profile.rawValue, forKey: Key.profile)
    }

    func set(_ categories: [CleaningCategory], enabled: Bool, available: [CleaningCategory]) {
        if profile != .custom {
            customIDs = Set(self.categories(from: available).map(\.id))
        }
        if enabled { customIDs.formUnion(categories.map(\.id)) }
        else { customIDs.subtract(categories.map(\.id)) }
        defaults.set(customIDs.sorted(), forKey: Key.custom)
        select(.custom)
    }

    static var currentCategories: [CleaningCategory] {
        ScanPreferences().categories(from: CleaningCategory.visible)
    }
}
