import Foundation

/// Préférences de présentation et de recherche ; aucun réglage ne change les gardes de suppression.
struct FileStoragePreferences {
    enum Key {
        static let large = "filesSearchLarge"
        static let duplicates = "filesSearchDuplicates"
        static let minSize = "filesMinimumSize"
        static let age = "filesMinimumAge"
        static let view = "spaceDisplayMode"
        static let start = "spaceStartFolder"
    }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var searchLarge: Bool { defaults.object(forKey: Key.large) as? Bool ?? true }
    var searchDuplicates: Bool { defaults.object(forKey: Key.duplicates) as? Bool ?? true }
    var hasSearch: Bool { searchLarge || searchDuplicates }
    var minSize: LargeFilesModel.MinSize {
        LargeFilesModel.MinSize(rawValue: UInt64(max(0, defaults.integer(forKey: Key.minSize)))) ?? .mb100
    }
    var age: LargeFilesModel.Age { LargeFilesModel.Age(rawValue: defaults.integer(forKey: Key.age)) ?? .any }
    var spaceView: SpaceDisplayMode { SpaceDisplayMode(rawValue: defaults.string(forKey: Key.view) ?? "") ?? .map }
    var spaceStart: SpaceStartFolder { SpaceStartFolder(rawValue: defaults.string(forKey: Key.start) ?? "") ?? .startupDisk }
}

enum SpaceDisplayMode: String, CaseIterable, Identifiable {
    case map, list
    var id: String { rawValue }
    var title: String { self == .map ? "Carte" : "Liste" }
}

enum SpaceStartFolder: String, CaseIterable, Identifiable {
    case startupDisk, home, desktop, documents, downloads, movies, library
    var id: String { rawValue }
    var relativePath: String {
        switch self {
        case .startupDisk, .home: return ""
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        case .downloads: return "Downloads"
        case .movies: return "Movies"
        case .library: return "Library"
        }
    }
    var title: String {
        switch self {
        case .startupDisk: return "Disque de démarrage"
        case .home: return "Dossier personnel"
        case .desktop: return "Bureau"
        case .documents: return "Documents"
        case .downloads: return "Téléchargements"
        case .movies: return "Séquences"
        case .library: return "Bibliothèque"
        }
    }
    var path: String { if self == .startupDisk { return "/" }; return relativePath.isEmpty ? NSHomeDirectory() : (NSHomeDirectory() as NSString).appendingPathComponent(relativePath) }
}
