import Foundation

/// Aperçu volontaire et temporaire : aucun état n’est enregistré dans les préférences.
enum AppUpdatePreview {
    static func isEnabled(info: [String: Any], arguments: [String]) -> Bool {
        info["MacCareDevelopmentBuild"] as? Bool == true && arguments.contains("--preview-available-update")
    }

    static let version = "0.2.99"
    static let notes = """
    **Aperçu : mise à jour fictive**
    Ces nouveautés servent uniquement à présenter l’onglet À propos.

    **Nouveautés**
    - Retrouvez les nouveautés et le téléchargement dans À propos.
    - Un contour orange signale qu’une mise à jour est disponible.
    - Accédez au site, à la documentation et au code source depuis la même page.

    **Améliorations**
    - Une présentation plus lisible des notes de version.
    - Une navigation qui conserve vos outils à portée de main.
    """
}
