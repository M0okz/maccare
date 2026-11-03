import AppKit
import Foundation

/// Identité stable d'un fichier, miroir de `maccare_core::FileIdentity`.
struct FileIdentity: Codable, Hashable {
    let device: UInt64
    let inode: UInt64
}

/// Un élément proposé par le scan.
struct ScanItem: Codable, Identifiable, Hashable {
    let id: String
    let path: String
    let category: String
    let size_bytes: UInt64
    let reason: String
    let autoselect: Bool
    let identity: FileIdentity
    /// App à laquelle appartient l'élément quand il s'agit d'un sous-dossier (ex. ses caches).
    let owner: String?

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String {
        guard let owner else { return url.lastPathComponent }
        return "\(AppNames.name(for: owner)) — \(url.lastPathComponent)"
    }
}

/// Nom lisible d'une app à partir du nom de son dossier de données : identifiant de bundle
/// (conteneurs) résolu via LaunchServices, sinon le nom tel quel (« Slack », « Code »…).
enum AppNames {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func name(for owner: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[owner] { return hit }
        var resolved = owner
        if owner.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: owner) {
            resolved = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        cache[owner] = resolved
        return resolved
    }
}

struct ScanResponse: Codable {
    let items: [ScanItem]?
    let warnings: [String]?
    let error: String?
    let cancelled: Bool?
}

/// Entrée de l'inspection de chemins explicites (désinstalleur).
struct InspectInput: Encodable {
    let category: String
    let paths: [String]
}

/// Un élément soumis à la validation de sûreté avant mise à la corbeille.
struct PlanItem: Encodable {
    let path: String
    let identity: FileIdentity
}

struct PlanInput: Encodable {
    let scope_root: String
    let items: [PlanItem]
    /// Texte TOML de la règle qui a produit ces éléments (même chaîne que pour le scan).
    /// Le moteur re-vérifie alors que chaque élément correspond encore à la règle, et n'autorise un
    /// chemin situé dans un dossier protégé (~/Downloads) que si la règle déclare une liste d'inclusion.
    /// Absente (`nil`) : comportement historique, la clé n'est pas envoyée.
    var rule: String? = nil
}

/// Décision de sûreté rendue par le moteur pour un chemin.
/// Un gros fichier trouvé par le moteur (module « Gros fichiers »).
struct LargeFile: Codable, Identifiable, Hashable {
    let path: String
    let size_bytes: UInt64
    /// Dernière modification, secondes depuis l'époque Unix.
    let modified: Int64
    let identity: FileIdentity

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }
}

struct LargeFilesInput: Encodable {
    var root: String? = nil
    let min_bytes: UInt64
    let limit: Int
}

struct LargeFilesResponse: Codable {
    let root: String?
    let files: [LargeFile]?
    let warnings: [String]?
    let complete: Bool?
    let cancelled: Bool?
    let error: String?
}

/// Un fichier d'un groupe de doublons.
struct DupFile: Codable, Identifiable, Hashable {
    let path: String
    let size_bytes: UInt64
    let modified: Int64
    let identity: FileIdentity

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }
}

/// Des fichiers au contenu identique (du plus ancien au plus récent).
struct DupGroup: Codable, Identifiable, Hashable {
    let length: UInt64
    var files: [DupFile]
    /// Attribué à la réception, stable même quand des copies quittent le groupe.
    var id = UUID().uuidString

    private enum CodingKeys: String, CodingKey { case length, files }

    /// Espace libéré en ne gardant qu'un exemplaire (recalculé quand des copies partent).
    var reclaimable: UInt64 {
        files.reduce(0) { $0 + $1.size_bytes } - (files.map(\.size_bytes).max() ?? 0)
    }
}

struct DuplicatesInput: Encodable {
    var root: String? = nil
    let min_bytes: UInt64
}

struct DuplicatesResponse: Codable {
    let root: String?
    let groups: [DupGroup]?
    let warnings: [String]?
    let complete: Bool?
    let cancelled: Bool?
    let error: String?
}

struct DuplicatesPlanGroup: Encodable {
    let keep: PlanItem
    let remove: [PlanItem]
}

struct DuplicatesPlanInput: Encodable {
    let root: String
    let groups: [DuplicatesPlanGroup]
}

/// Une corbeille repérée par le moteur.
struct TrashBin: Codable, Identifiable, Hashable {
    let path: String
    let label: String
    let identity: FileIdentity
    let items: Int
    let size_bytes: UInt64
    let measured: Bool
    /// Faux sans Accès complet au disque : contenu inconnu, pas « vide ».
    let readable: Bool
    /// Empreinte du contenu affiché : le moteur refuse de vider si le contenu a changé depuis.
    let snapshot: String

    var id: String { path }
}

struct TrashListResponse: Codable {
    let bins: [TrashBin]?
    let cancelled: Bool?
    let error: String?
}

struct TrashEmptyItem: Encodable {
    let path: String
    let identity: FileIdentity
    let snapshot: String
}

struct TrashEmptyInput: Encodable {
    let bins: [TrashEmptyItem]
}

struct TrashFailure: Codable, Hashable {
    let path: String
    let error: String
}

struct TrashEmptyResult: Codable {
    let path: String
    let refusal: String?
    let removed: Int
    let freed_bytes: UInt64
    let failures: [TrashFailure]
}

struct TrashEmptyResponse: Codable {
    let results: [TrashEmptyResult]?
    let cancelled: Bool?
    let error: String?
}

/// Un simulateur Xcode.
struct SimDevice: Codable, Identifiable, Hashable {
    let udid: String
    let name: String
    let runtime: String
    let state: String
    /// Faux si son runtime n'est plus installé : inutilisable.
    let available: Bool
    let last_used: String?
    let size_bytes: UInt64

    var id: String { udid }
    var isBooted: Bool { state != "Shutdown" }
}

/// Un runtime de simulateur (image système téléchargée).
struct SimRuntimeInfo: Codable, Identifiable, Hashable {
    let identifier: String
    let name: String
    let size_bytes: UInt64
    let deletable: Bool
    let last_used: String?
    let devices: Int

    var id: String { identifier }
}

struct SimulatorsResponse: Codable {
    let xcode: Bool?
    let simulators: [SimDevice]?
    let runtimes: [SimRuntimeInfo]?
    let warnings: [String]?
    let cancelled: Bool?
    let error: String?
}

struct SimDeleteInput: Encodable {
    let simulators: [String]
    let runtimes: [String]
}

struct SimDeleteResult: Codable {
    let id: String
    let removed: Bool
    let error: String?
}

struct SimDeleteResponse: Codable {
    let results: [SimDeleteResult]?
    let error: String?
}

/// Un agent de lancement, tel que lu par le moteur.
struct LaunchAgentInfo: Codable, Identifiable, Hashable {
    let path: String
    let label: String
    /// `user`, `disabled` (mis de côté par MacCare) ou `system` (lecture seule).
    let scope: String
    let program: String?
    /// Programme introuvable : l'app a probablement été supprimée.
    let orphan: Bool
    let loaded: Bool
    let running: Bool
    /// Faux si l'état chargé/en cours est inconnu (système, ou launchctl illisible).
    let state_known: Bool
    /// Outil qui gère l'agent (ex. « Homebrew ») et peut le réactiver de lui-même.
    let managed_by: String?
    let apple: Bool
    let identity: FileIdentity?
    let original_path: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var canDisable: Bool { scope == "user" && !apple && identity != nil }
}

struct AgentsResponse: Codable {
    let agents: [LaunchAgentInfo]?
    let error: String?
}

struct AgentActionInput: Encodable {
    let action: String
    let path: String
    let identity: FileIdentity
}

struct AgentActionResponse: Codable {
    let ok: Bool?
    let path: String?
    let error: String?
}

struct UserFilesPlanInput: Encodable {
    let root: String
    let items: [PlanItem]
}

struct RemovalDecision: Codable {
    let path: String
    let allowed: Bool
    let refusal: String?
}

struct PlanResponse: Codable {
    let decisions: [RemovalDecision]?
    let error: String?
}

/// Résultat d'une suppression directe exécutée par le moteur.
struct RemovalResult: Codable {
    let path: String
    let allowed: Bool
    let refusal: String?
    let removed: Bool
    let error: String?
}

struct ExecuteResponse: Codable {
    let results: [RemovalResult]?
    let error: String?
}

// MARK: - Espace disque

/// Un enfant direct d'un dossier exploré, miroir de `maccare_core::scan::DirChild`.
struct SpaceChild: Codable, Identifiable, Hashable {
    let path: String
    let size_bytes: UInt64
    let is_dir: Bool
    let measured: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

struct MeasureInput: Encodable {
    let path: String
    let budget_secs: UInt64
}

struct MeasureResponse: Codable {
    let path: String?
    let children: [SpaceChild]?
    let warnings: [String]?
    let error: String?
    let cancelled: Bool?
}
