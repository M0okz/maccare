import Foundation

/// Presentation profiles only. A match labels an existing engine result and never creates a removal target.
struct SmartScanAppProfile: Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let impact: String
    let protectedData: String

    static let supported = [
        Self(id: "com.google.Chrome", name: "Google Chrome", aliases: ["Google Chrome", "Chrome"],
             impact: "Les pages peuvent recharger leurs images et leurs scripts lors de la prochaine visite.",
             protectedData: "Les favoris, les mots de passe et les profils du navigateur restent à leur emplacement."),
        Self(id: "com.tinyspeck.slackmacgap", name: "Slack", aliases: ["Slack"],
             impact: "Slack téléchargera de nouveau les aperçus et les images dont vous avez besoin.",
             protectedData: "Les espaces de travail et les données de connexion sont conservés."),
        Self(id: "com.spotify.client", name: "Spotify", aliases: ["Spotify"],
             impact: "Les pochettes et les ressources en cache pourront être téléchargées à nouveau.",
             protectedData: "La musique hors ligne se gère dans Spotify. Seuls les caches visuels reconnus et les journaux sont proposés dans cette fiche."),
        Self(id: "com.microsoft.VSCode", name: "Visual Studio Code", aliases: ["Code", "Visual Studio Code"],
             impact: "L’éditeur peut prendre un peu plus de temps à rouvrir ses vues après la suppression des caches.",
             protectedData: "Vos projets, extensions et réglages utilisateur sont conservés."),
        Self(id: "com.apple.dt.Xcode", name: "Xcode", aliases: ["Xcode"],
             impact: "La documentation et les fichiers de prise en charge peuvent demander un nouveau téléchargement. Conservez les archives des versions publiées pour analyser leurs plantages.",
             protectedData: "Vos projets et sources restent en place. Les archives signalées « À revoir » demandent un choix explicite."),
        Self(id: "org.mozilla.firefox", name: "Firefox", aliases: ["Firefox"],
             impact: "Firefox rechargera les ressources des sites à la prochaine visite.",
             protectedData: "Les profils contenant les favoris et les identifiants restent dans le dossier de données du navigateur."),
        Self(id: "com.hnc.Discord", name: "Discord", aliases: ["Discord"],
             impact: "Les images et aperçus de vos salons pourront être téléchargés de nouveau.",
             protectedData: "Les comptes, les réglages et les fichiers enregistrés dans Téléchargements sont conservés."),
        Self(id: "notion.id", name: "Notion", aliases: ["Notion"],
             impact: "Les ressources visuelles des pages pourront se recharger à leur prochaine ouverture.",
             protectedData: "Le stockage local des espaces de travail et les données de connexion sont conservés."),
        Self(id: "us.zoom.xos", name: "Zoom", aliases: ["Zoom", "zoom.us"],
             impact: "Les journaux sélectionnés disparaîtront et Zoom recréera ses caches à l’usage.",
             protectedData: "Les enregistrements de réunions dans leur dossier habituel sont conservés."),
        Self(id: "com.microsoft.teams2", name: "Microsoft Teams", aliases: ["com.microsoft.teams", "Microsoft Teams", "MSTeams"],
             impact: "Les images et aperçus des conversations pourront être rechargés au prochain lancement.",
             protectedData: "Les comptes et les dossiers partagés de Microsoft 365 sont conservés.")
    ]

    static let other = Self(id: "other", name: "Autres résultats", aliases: [],
                            impact: "Ces éléments sont classés ci-dessous selon leur catégorie d’origine.",
                            protectedData: "Les emplacements partagés ou dont le propriétaire est incertain restent dans ce groupe.")

    private static let byOwner = Dictionary(uniqueKeysWithValues: supported.flatMap { profile in
        ([profile.id] + profile.aliases).map { ($0.lowercased(), profile.id) }
    })

    static func knownOwner(_ name: String) -> String? { byOwner[name.lowercased()] }

    // A sandbox can keep offline audio alongside disposable caches. An opaque Caches
    // directory provides no way to distinguish them, even when its owner is known.
    static func includes(_ item: ScanItem, containerOwners: [String: String]) -> Bool {
        guard item.category == "container-cache", let owner = item.owner else { return true }
        return knownOwner(containerOwners[owner] ?? owner) != "com.spotify.client"
    }

    static func identifier(for item: ScanItem, containerOwners: [String: String]) -> String {
        if item.reason.hasPrefix("xcode."), item.category.hasPrefix("xcode-") { return "com.apple.dt.Xcode" }
        if item.category == "user-cache", item.owner?.lowercased() == "google", item.url.lastPathComponent == "Chrome" {
            return "com.google.Chrome"
        }
        switch item.category {
        case "user-cache", "user-logs", "container-cache", "electron-cache":
            let owner = item.owner ?? item.url.lastPathComponent
            return byOwner[(containerOwners[owner] ?? owner).lowercased()] ?? other.id
        default:
            return other.id
        }
    }
}

struct SmartScanAppResult: Identifiable {
    let profile: SmartScanAppProfile
    let sections: [ScanGroup]
    var id: String { profile.id }
    var items: [ScanItem] { sections.flatMap(\.items) }
    var bytes: UInt64 { sections.reduce(0) { $0 + $1.size } }
    var count: Int { sections.reduce(0) { $0 + $1.items.count } }

    static func group(_ groups: [ScanGroup]) -> [Self] {
        var sections: [String: [ScanGroup]] = [:]
        for group in groups {
            let partition = Dictionary(grouping: group.items) {
                SmartScanAppProfile.identifier(for: $0, containerOwners: group.containerOwners)
            }
            for (id, items) in partition {
                sections[id, default: []].append(ScanGroup(category: group.category, items: items))
            }
        }
        var results = SmartScanAppProfile.supported.map { Self(profile: $0, sections: sections[$0.id] ?? []) }
        results.sort {
            $0.bytes == $1.bytes ? $0.profile.name.localizedStandardCompare($1.profile.name) == .orderedAscending : $0.bytes > $1.bytes
        }
        results.append(Self(profile: .other, sections: sections[SmartScanAppProfile.other.id] ?? []))
        return results
    }
}
