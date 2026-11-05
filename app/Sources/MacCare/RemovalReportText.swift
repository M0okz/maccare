import Foundation

extension RemovalReport {
    /// Explication, en français, d'un code de refus du moteur.
    static func explain(_ code: String) -> String {
        switch code {
        case "identity-changed": return "l'élément a changé depuis l'analyse"
        case "protected": return "chemin protégé"
        case "outside-scope": return "hors du périmètre de nettoyage"
        case "rule-mismatch": return "ne correspond plus à la règle"
        case "no-kept-copy": return "aucune copie conservée ne serait garantie"
        case "not-duplicate": return "n'est plus identique à la copie conservée"
        case "not-eligible": return "pas un fichier proposable (dossier, caché ou dans une app)"
        case "symlink": return "lien symbolique"
        case "stat-error": return "élément illisible"
        default: return code
        }
    }

    /// Résumé d'une ligne : « 1 mis à la corbeille, 1 refusé par sûreté (chemin protégé) ».
    var summary: String {
        let verb = direct ? pl(removed, "supprimé") : "mis à la corbeille"
        var parts = ["\(removed) \(verb)"]
        if !refused.isEmpty {
            let reasons = Set(refused.map { Self.explain($0.reason) }).sorted().joined(separator: ", ")
            parts.append("\(refused.count) \(pl(refused.count, "refusé")) par sûreté (\(reasons))")
        }
        if !failed.isEmpty { parts.append("\(failed.count) en échec") }
        return parts.joined(separator: ", ")
    }

    /// Vrai s'il y a eu des refus ou des échecs : le compte rendu s'affiche alors en alerte.
    var needsAttention: Bool { !refused.isEmpty || !failed.isEmpty }
}
