import Foundation

/// Réglage « Outils pour développeurs » : affiche les catégories et modules propres aux
/// développeurs (Xcode, simulateurs, caches d'outils). Désactivé, ces catégories ne sont ni
/// affichées, ni analysées, ni cochées.
///
/// Par défaut, il suit la présence d'outils de développement sur ce Mac (`~/Library/Developer`) ;
/// dès que l'utilisateur le règle, son choix fait foi.
enum DeveloperTools {
    static let key = "developerTools"

    static var defaultValue: Bool {
        FileManager.default.fileExists(atPath: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Developer"))
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: key) == nil ? defaultValue : UserDefaults.standard.bool(forKey: key)
    }
}
