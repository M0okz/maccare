import Foundation

/// Les destinations techniques restent stables ; seules leurs entrées de navigation sont regroupées.
enum NavigationSection: String, CaseIterable, Identifiable {
    case home, cleaning, performance, applications, files, space, tools, battery, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .about: return "À propos"
        case .battery: return "Batterie"
        case .home: return "Accueil"
        case .cleaning: return "Nettoyage"
        case .performance: return "Performances"
        case .space: return "Espace disque"
        case .files: return "Mes fichiers"
        case .applications: return "Applications"
        case .tools: return "Mes outils"
        }
    }
    var symbol: String {
        switch self {
        case .about: return "info.circle"
        case .battery: return "battery.100percent"
        case .home: return "house"
        case .cleaning: return "sparkle.magnifyingglass"
        case .performance: return "bolt"
        case .space: return "chart.pie"
        case .files: return "folder"
        case .applications: return "app.badge"
        case .tools: return "briefcase"
        }
    }
    var destinations: [Module] {
        switch self {
        case .about: return [.about]
        case .battery: return [.battery]
        case .home: return [.dashboard]
        case .performance: return [.performanceOverview]
        case .cleaning: return [.cleaningOverview, .smartScan, .cleaning, .systemClean, .trash, .devJunk, .simulators]
        case .space: return [.space]
        case .files: return [.filesOverview, .largeFiles, .duplicates, .imageOptimization]
        case .applications: return [.applicationsOverview, .uninstall, .updates]
        case .tools: return [.toolsOverview, .screenCleaning, .aiClutter, .applicationPermissions, .maintenance, .startup, .privacy, .diskHealth]
        }
    }
    var defaultDestination: Module { destinations[0] }
    func destinations(developerTools: Bool) -> [Module] {
        destinations.filter { developerTools || !$0.isDeveloper }
    }
    static let primary: [Self] = [.home, .cleaning, .performance, .battery, .applications, .files, .space, .tools, .about]
}

extension Module {
    var section: NavigationSection {
        switch self {
        case .about: return .about
        case .battery: return .battery
        case .dashboard: return .home
        case .performanceOverview: return .performance
        case .cleaningOverview, .smartScan, .cleaning, .systemClean, .trash, .devJunk, .simulators: return .cleaning
        case .space: return .space
        case .filesOverview, .largeFiles, .duplicates, .imageOptimization: return .files
        case .applicationsOverview, .uninstall, .updates: return .applications
        case .toolsOverview, .startup, .privacy, .maintenance, .screenCleaning, .aiClutter, .applicationPermissions, .diskHealth: return .tools
        }
    }
    var tabTitle: String {
        switch self {
        case .smartScan: return "Résultats de l’analyse"
        case .cleaning: return "Par catégorie"
        case .systemClean: return "Système"
        case .devJunk: return "Développement"
        case .space: return "Explorer"
        case .uninstall: return "Installées et résidus"
        default: return title
        }
    }
}

/// Mémorise le dernier onglet de chaque rubrique, y compris après un accès direct depuis l'accueil.
struct NavigationHistory {
    private var remembered: [NavigationSection: Module] = [:]
    mutating func remember(_ module: Module) { remembered[module.section] = module }
    func destination(for section: NavigationSection, developerTools: Bool) -> Module {
        guard let module = remembered[section], developerTools || !module.isDeveloper else {
            return section.defaultDestination
        }
        return module
    }
}
