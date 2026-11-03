import Foundation

public enum PerformanceTask: String, CaseIterable, Codable, Sendable, Identifiable {
    case mail, purgeable, spotlight, permissions, dns
    public var id: String { rawValue }
    public var requiresHelper: Bool { self == .purgeable || self == .spotlight || self == .permissions || self == .dns }
    public func requiresHelper(includeLocalSnapshots: Bool) -> Bool {
        self == .purgeable ? includeLocalSnapshots : requiresHelper
    }
    public var title: String {
        switch self {
        case .mail: return "Accélérer Mail"
        case .purgeable: return "Libérer l’espace purgeable"
        case .spotlight: return "Réindexer Spotlight"
        case .permissions: return "Réparer les autorisations du disque"
        case .dns: return "Vider le cache DNS"
        }
    }
    public var symbol: String {
        switch self {
        case .mail: return "envelope"
        case .purgeable: return "internaldrive"
        case .spotlight: return "magnifyingglass"
        case .permissions: return "externaldrive.badge.checkmark"
        case .dns: return "network"
        }
    }
    public var detail: String {
        switch self {
        case .mail: return "Compacte et optimise la base d’index de Mail, sans supprimer de message."
        case .purgeable: return "Libère des caches régénérables et, selon vos réglages, réduit les instantanés Time Machine locaux."
        case .spotlight: return "Demande à macOS de reconstruire l’index du disque de démarrage."
        case .permissions: return "Rétablit les autorisations du dossier personnel de votre compte avec l’outil macOS."
        case .dns: return "Réinitialise les résolutions de noms conservées localement par macOS."
        }
    }
    public var effect: String {
        switch self {
        case .mail: return "Quittez Mail avant de continuer et laissez-le fermé pendant l’opération. MacCare compacte sa base SQLite existante et contrôle son intégrité. Les messages et pièces jointes restent en place. Aucun gain de vitesse n’est garanti."
        case .purgeable: return "Les caches examinés sont supprimés définitivement. Si l’option des réglages est activée, macOS réduit aussi les instantanés Time Machine locaux éligibles : certains points de restauration présents sur ce Mac sont alors supprimés définitivement. Les sauvegardes sur disque externe ou réseau ne sont pas visées. Le gain dépend de ce que macOS peut libérer et peut apparaître avec un délai."
        case .spotlight: return "La recherche peut fournir des résultats incomplets pendant la réindexation et le Mac peut ralentir temporairement. L’indexation continue sous le contrôle de macOS après la fin de la commande. Un index volontairement désactivé ne sera pas réactivé automatiquement."
        case .permissions: return "macOS réinitialise les autorisations du dossier personnel du compte connecté. Cela peut modifier des autorisations personnalisées. Le volume système scellé et les autres comptes ne sont pas visés. Cette réparation n’accorde pas les autorisations Confidentialité et sécurité."
        case .dns: return "Les prochaines connexions devront résoudre à nouveau leurs noms. Les serveurs DNS, le VPN et la configuration réseau restent identiques."
        }
    }
}

public struct MaintenanceReport: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case completed, started, partial, failed }
    public let status: Status
    public let message: String
    public let details: String
    public var succeeded: Bool { status == .completed || status == .started }
    public init(_ status: Status, _ message: String, details: String = "") {
        self.status = status; self.message = message; self.details = details
    }
}
