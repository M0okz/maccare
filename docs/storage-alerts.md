# Alerte d’espace disque

Disponible depuis [MacCare 0.2.8 (build 10)](https://github.com/M0okz/maccare/releases/tag/v0.2.8), publiée le 6 novembre 2026
(heure de Paris). Installation de cette version vérifiée dans
`/Applications/MacCare.app` via Sparkle, depuis 0.2.6 (8). Le paquet installé
correspond au binaire public signé et notarié. Les validations de développement
ci-dessous restent datées et conservent leurs limites.

Historique de développement : branche `codex/menu-bar-alerts`, mise à jour
sur la base 0.2.5 avant intégration dans la PR nº 4.

Une bulle ancrée sous l’icône MacCare signale un espace disponible inférieur
à 10 Go ou représentant au plus 10 % de la capacité du disque de démarrage.
Le volume, son nom et la capacité disponible pour un usage important proviennent
de macOS, via `SpaceVolumeUsage`. Les valeurs invalides ne déclenchent rien.

La surveillance est active lorsque MacCare et sa barre des menus sont ouverts,
après la configuration initiale. Première vérification après une minute,
puis toutes les cinq minutes. Elle attend si MacCare est au premier plan,
si son grand volet est affiché, ou pendant une analyse/un nettoyage Smart Scan. La veille
interrompt le suivi ; le réveil le relance avec un délai d’une minute.
Un rappel au maximum toutes les 24 heures. Les choix « Pendant une journée »
et « Pendant une semaine » utilisent les jours calendaires et persistent après
un relancement. Le bouton « Ouvrir MacCare » affiche le Smart Scan, sans le
lancer et sans supprimer de fichiers.

Dans Réglages > Barre des menus, l’alerte est désactivable et un aperçu fictif
est disponible. L’aperçu affiche un exemple à 43,17 Go libres ; il ne modifie
ni le dernier rappel ni un report réel. Il n’utilise pas le centre de
notifications macOS et ne demande pas d’autorisation de notification.

Le panneau AppKit ne vole pas le premier plan. Son fond est une unique
`NSVisualEffectView` avec le matériau natif `popover` ; le masque inclut la
pointe. Un trait sombre d’un point suit la forme et l’ombre vient de la fenêtre.
Aucun bord lumineux de verre ni couche de transparence simulée. L’apparence
hérite du système (clair/sombre), avec couleurs sémantiques et bouton bleu.
La touche Échap et le clic extérieur ferment la bulle. Les contrôles sont des
boutons et menus SwiftUI natifs ; le disque et sa capacité ont une description
d’accessibilité commune, indépendante de la couleur de la jauge.

Depuis le 4 novembre, `MenuBarAlertPresenter` partage la présentation et les
gestes de fermeture avec l’alerte mémoire, sans changer le rendu disque.
`TrayPanelController` empêche les deux alertes automatiques de se superposer.

Composants : `StorageAlertPolicy`, `StorageAlertController`, `StorageAlertPanel`,
`StorageAlertOutlineView`, `StorageAlertView`, `StorageAlertPrimaryButtonStyle`,
`StorageAlertSettingsView`, avec intégration dans `TrayPanelController` et
`SettingsView`. Préférences : `storageAlert.enabled` (vrai par défaut),
`storageAlert.lastShown`, `storageAlert.snoozedUntil`.

Les tests `StorageAlertTests` couvrent les seuils, les relevés invalides,
la désactivation, la récupération d’espace, les délais et la persistance.
Validation du 3 novembre 2026 : 9 tests ciblés réussis (5 pour la politique
d’alerte, 4 pour la disposition du grand volet), build Release réussi,
paquet `build/development/MacCare.app` assemblé et signature Apple Development
vérifiée, plist valide et `git diff --check` sans erreur. Les apparences claire
et sombre, l’arbre d’accessibilité, les deux entrées du menu Ignorer, Échap et
l’appel de l’action principale ont été vérifiés dans l’hôte QA isolé. Le
changement de couleur n’est pas forcé dans le composant de production.

Les preuves sont conservées sous `build/notification-validation/`.
La QA visuelle utilise un hôte isolé, avec
son propre identifiant `local.qa.maccare-storage-alert`, sans lancer ni
remplacer la copie utilisateur. Une campagne VoiceOver complète et un test
de veille/réveil réel restent à effectuer.
