import Foundation

/// Protocole XPC entre MacCare et son assistant privilégié (`MacCareHelper`).
///
/// Opérations fermées, rien d'autre (voir `docs/architecture.md`). Les règles sont des
/// identifiants **compilés dans le moteur** (`sys.logs.rotated`…). Seule exception aux chemins :
/// `uninstall`, limitée à une application de `/Applications` ou `~/Applications` et aux emplacements
/// fermés d’`AuthorizedUninstall`, avec contrôle d’identité de chaque élément. Aucune opération
/// « exécuter ceci ». Les réponses sont du JSON.
@objc public protocol MacCareHelperXPC {
    /// Version du protocole et de l'assistant (comparées à la connexion).
    func version(withReply reply: @escaping (Int, String) -> Void)
    /// Éléments d'une règle : `{"items":[...],"skipped":[...],"truncated"}` ou `{"error"}`.
    func list(rule: String, withReply reply: @escaping (String) -> Void)
    /// Supprime **définitivement** les éléments désignés par identité (`[{"device","inode"}]`),
    /// après réénumération de la règle par l'assistant.
    func remove(rule: String, identitiesJSON: String, withReply reply: @escaping (String) -> Void)
    /// Synthèse du journal d'audit depuis une date, **sans chemins**.
    /// Tâche fermée (purgeable, dns, spotlight, permissions). UID déterminé par la connexion authentifiée.
    func maintenance(task: String, withReply reply: @escaping (String) -> Void)
    /// Commande batterie fermée ; validation des seuils et contrôle matériel dans l’assistant.
    func battery(command: String, sessionID: String, configurationJSON: String, withReply reply: @escaping (String) -> Void)
    func fan(preset: String, withReply reply: @escaping (String) -> Void)
    func journal(since: Date, withReply reply: @escaping (String) -> Void)
    /// Retire la sélection d’un désinstalleur (`AuthorizedUninstall` encodé) pour l’UID de la
    /// connexion, après confirmation par Touch ID ou mot de passe dans l’app.
    /// Réponse : `[AuthorizedUninstall.Result]` ou `{"error"}`.
    func uninstall(selectionJSON: String, withReply reply: @escaping (String) -> Void)
}

/// Identités et exigences partagées entre l'app et l'assistant.
public enum HelperIdentity {
    public static let machService = "org.maccare.helper"
    public static let daemonPlist = "org.maccare.helper.plist"
    // Version 11 adds bounded fan presets and restoration before service removal.
    // Version 12 adds the uninstaller's selection, confirmed in the app with Touch ID.
    public static let protocolVersion = 12

    /// Équipe de signature (Developer ID et certificats de développement de la même équipe).
    public static let teamID = "5FAF9ZA2X9"

    /// Exigence imposée par l'assistant à **chaque message** de l'app.
    public static let appRequirement =
        "anchor apple generic and identifier \"org.maccare.app\" and certificate leaf[subject.OU] = \"\(teamID)\""

    /// Exigence imposée par l'app à l'assistant (on ne parle qu'au vrai assistant).
    public static let helperRequirement =
        "anchor apple generic and identifier \"org.maccare.helper\" and certificate leaf[subject.OU] = \"\(teamID)\""
}


public enum FanPreset: String, CaseIterable, Sendable {
    case automatic, cool, maximum

    public var title: String {
        switch self {
        case .automatic: return "Auto"
        case .cool: return "Frais"
        case .maximum: return "Max"
        }
    }
}
