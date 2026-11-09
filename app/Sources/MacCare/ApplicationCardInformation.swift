import Foundation

/// Les explications décrivent les critères réellement utilisés, sans transformer un signal en verdict.
enum ApplicationCardInformation: String, CaseIterable {
    case updates, unused, incompatible, installers, leftovers, startup

    var title: String {
        switch self {
        case .updates: return "Mises à jour des applications"
        case .unused: return "Applications peu utilisées"
        case .incompatible: return "Applications incompatibles"
        case .installers: return "Fichiers d’installation"
        case .leftovers: return "Données d’applications supprimées"
        case .startup: return "À l’ouverture du Mac"
        }
    }

    var summary: String {
        switch self {
        case .updates: return "MacCare consulte plusieurs sources en parallèle pour repérer les mises à jour de vos applications."
        case .unused: return "Une ouverture ancienne est un indice pour faire le tri, pas une preuve que l’application ne vous sert plus."
        case .incompatible: return "Cette catégorie rassemble les blocages que MacCare peut identifier pour votre Mac et votre version de macOS."
        case .installers: return "Ce sont les images disque et paquets d’installation trouvés directement dans votre dossier Téléchargements."
        case .leftovers: return "MacCare recherche des données qui semblent appartenir à des applications absentes de l’inventaire."
        case .startup: return "Retrouvez les éléments d’ouverture et les agents qui peuvent se lancer avec votre session."
        }
    }

    var criteria: [String] {
        switch self {
        case .updates: return []
        case .unused: return [
            "Au moins \(ApplicationInsightPolicy.unusedDays) jours depuis la dernière ouverture enregistrée par Spotlight.",
            "Au moins \(ApplicationInsightPolicy.graceDays) jours depuis l’arrivée de l’app à son emplacement actuel.",
            "Les apps ouvertes, les agents et les dates inconnues ou futures sont écartés."
        ]
        case .incompatible: return [
            "Vérification des architectures du binaire principal et des versions minimales de macOS déclarées par l’app.",
            "Une app Intel sur Apple Silicon n’est pas classée incompatible pour ce seul motif : elle peut fonctionner avec Rosetta.",
            "Ce contrôle ne lance pas l’app et ne vérifie pas toutes ses extensions, dépendances ou signatures."
        ]
        case .installers: return [
            "Seuls les fichiers DMG et PKG sont retenus, pas les ZIP ni les téléchargements à extension partielle.",
            "Leur présence ne permet pas de savoir si l’installation a été faite ou si vous souhaitez les conserver.",
            "Aucun fichier n’est coché au départ. Vous examinez la sélection avant de confirmer sa mise à la Corbeille."
        ]
        case .leftovers: return [
            "L’association repose sur les noms et identifiants repérés ; le propriétaire indiqué reste présumé.",
            "Un cache, une préférence ou un dossier de support peut contenir des réglages ou des données à conserver.",
            "Consultez les chemins et choisissez les éléments à retirer. La sélection initiale est vide."
        ]
        case .startup: return [
            "Les éléments d’ouverture et les agents d’arrière-plan sont présentés séparément.",
            "Certains réglages se modifient dans les Réglages Système et peuvent dépendre des autorisations accordées.",
            "Les agents système restent en lecture seule. Examinez l’origine d’un élément avant de le désactiver."
        ]
        }
    }

    var footnote: String {
        switch self {
        case .updates: return "Aucune mise à jour n’est installée automatiquement."
        case .unused: return "Les usages directs en ligne de commande ou en arrière-plan peuvent ne pas actualiser Spotlight. Aucune désinstallation automatique."
        case .incompatible: return "La carte apparaît seulement lorsqu’un blocage est repéré. L’absence de résultat ne garantit pas que toutes les apps fonctionneront."
        case .installers: return "L’analyse seule ne supprime rien et ne modifie aucune application installée."
        case .leftovers: return "L’absence d’une app dans l’inventaire ne prouve pas que toutes ses données sont devenues inutiles."
        case .startup: return "Ouvrir ce gestionnaire ne désactive aucun élément."
        }
    }
}
