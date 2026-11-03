import Foundation

/// Niveau de risque d'une règle de nettoyage : décide de la présélection et du badge.
enum RuleRisk: String, Hashable {
    case safe     // régénérable sans conséquence
    case review   // peut contenir des données de l'utilisateur : toujours à confirmer
}

/// Public d'une règle : tout le monde, ou les utilisateurs ayant activé les outils pour développeurs.
enum RuleAudience: String, Hashable {
    case everyone
    case developer
}

/// Échappe une valeur pour une chaîne TOML « basic ».
func tomlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

/// Une catégorie de nettoyage, décrite par une règle au format ouvert (fichier TOML embarqué).
/// Le moteur Rust reste la seule autorité : l'app ne fait que lire les métadonnées et lui
/// transmettre le texte de la règle.
struct CleaningCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let category: String
    let risk: RuleRisk
    /// Nom de symbole SF Symbols.
    let icon: String
    /// Racine développée : sert aussi de périmètre de confinement à la suppression.
    let root: String
    /// Vrai si l'utilisateur peut régler un seuil de taille minimale (Réglages).
    let usesThreshold: Bool
    let audience: RuleAudience
    /// Texte TOML de la règle, tel que livré.
    let baseTOML: String

    /// Règle prête à scanner : on y ajoute le seuil réglé par l'utilisateur et ses exclusions.
    /// Ces blocs `[[exclude]]` s'ajoutent après ceux de la règle (tableaux de tables TOML).
    func ruleTOML(thresholdBytes: UInt64?, userExclusions: [String]) -> String {
        var extra: [String] = []
        if usesThreshold, let t = thresholdBytes {
            extra.append("[[exclude]]\nkind = \"max-size\"\nbytes = \(t)")
        }
        for path in userExclusions {
            extra.append("[[exclude]]\nkind = \"path-prefix\"\nvalue = \"\(tomlEscape(path))\"")
        }
        return ([baseTOML] + extra).joined(separator: "\n\n")
    }

    /// Toutes les catégories disponibles (jamais vide : repli sur deux règles intégrées).
    static let all: [CleaningCategory] = RuleCatalog.load()

    /// Catégories à afficher et analyser : celles pour développeurs seulement si l'option est
    /// activée (Réglages). Une catégorie masquée n'est ni scannée ni cochée.
    static var visible: [CleaningCategory] {
        all.filter { $0.audience == .everyone || DeveloperTools.enabled }
    }
}

/// Charge les règles embarquées dans `Contents/Resources/rules` du paquet.
enum RuleCatalog {
    static func load() -> [CleaningCategory] {
        var found: [CleaningCategory] = []
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("rules", isDirectory: true),
           let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let url as URL in files where url.pathExtension == "toml" {
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   let category = category(fromTOML: text) {
                    found.append(category)
                }
            }
        }
        if found.isEmpty { found = fallback.compactMap { category(fromTOML: $0) } }
        // Les règles sûres d'abord, puis celles à revoir ; ordre alphabétique à égalité.
        return found.sorted { a, b in
            let ra = a.risk == .safe ? 0 : 1, rb = b.risk == .safe ? 0 : 1
            return ra != rb ? ra < rb : a.title.localizedCompare(b.title) == .orderedAscending
        }
    }

    /// Construit une catégorie depuis le texte d'une règle ; nil si le moteur la rejette.
    static func category(fromTOML text: String) -> CleaningCategory? {
        guard let info = Engine.ruleInfo(text),
              let id = info.id, let category = info.category, let root = info.root else { return nil }
        let icon = (info.icon?.isEmpty == false) ? info.icon! : "sparkle.magnifyingglass"
        return CleaningCategory(
            id: id,
            title: info.title ?? id,
            summary: info.description ?? "",
            category: category,
            risk: info.risk == "review" ? .review : .safe,
            icon: icon,
            root: root,
            usesThreshold: info.min_size_setting ?? false,
            audience: info.audience == "developer" ? .developer : .everyone,
            baseTOML: text
        )
    }

    /// Règles minimales si les ressources embarquées sont introuvables (exécution hors paquet).
    private static let fallback: [String] = [
        """
        id = "cache.generic"
        category = "user-cache"
        version = 1
        root = "~/Library/Caches"
        depth = "per-app"
        title = "Caches utilisateur"
        description = "Caches d'applications régénérables, hors caches Apple."
        icon = "sparkle.magnifyingglass"

        [[exclude]]
        kind = "name"
        equals = ".DS_Store"

        [[exclude]]
        kind = "name-prefix"
        starts_with = "com.apple."
        """,
        """
        id = "logs.user"
        category = "user-logs"
        version = 1
        root = "~/Library/Logs"
        depth = "per-app"
        title = "Logs utilisateur"
        description = "Journaux d'applications, régénérés à l'usage."
        icon = "doc.text.fill"
        min_size_setting = true

        [[exclude]]
        kind = "name"
        equals = ".DS_Store"
        """,
    ]
}
