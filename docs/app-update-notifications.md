# Notifications des mises à jour de MacCare

## Préparation 0.2.25 — 10 novembre 2026

Branche `codex/app-store-session-context`, pas encore livrée à cette étape.
Le choix utilisateur est une bannière macOS lorsque MacCare reste actif, y compris
avec sa fenêtre fermée dans la barre des menus. Aucun serveur APNs n’est ajouté.
Ce suivi concerne les nouvelles versions de MacCare, pas les mises à jour des
applications tierces.

Sparkle conserve son flux HTTPS signé, son choix de recherche automatique et son
ordonnancement existant : contrôle au lancement lorsque les recherches automatiques
sont autorisées, puis intervalle configuré de 86400 secondes. La notification
arrive à la détection ; ce mécanisme n’est pas un push instantané. L’app complètement
quittée ne vérifie et n’envoie rien. Les recherches manuelles et les versions
critiques déjà présentées directement par Sparkle n’ajoutent pas de bannière.

`AppUpdateNotifications` vérifie l’autorisation système sans la demander en
arrière-plan, puis publie une requête locale sans son. Un identifiant de release
Sparkle déjà notifié est mémorisé pour éviter les répétitions entre relancements.
Un refus, une préférence désactivée ou un échec d’envoi ne consomme pas cette
alerte. Une seule livraison est en cours à la fois ; une désactivation ou une
attention utilisateur invalide et retire une livraison tardive.

Dans Réglages → Général → Mises à jour de MacCare, le réglage de notification est
actif par défaut, soumis à l’autorisation macOS. Le bouton Autoriser les notifications
et une réactivation explicite du réglage sont les seuls chemins de demande
d’autorisation. Un refus affiche un accès aux réglages système. Le réglage des
recherches automatiques reste distinct et continue d’être respecté.

Le `NotificationRouter` commun reste le seul délégué UNUserNotificationCenter.
Le clic sur `maccare.app-update` émet un événement interne consommé par l’AppUpdater,
indépendant de la présence d’une vue de fenêtre. La fenêtre est rouverte si nécessaire,
puis Sparkle affiche les nouveautés et les options d’installation. Si la recherche
initiale est occupée, l’ouverture est attendue jusqu’à `canCheckForUpdates`.
Les autres notifications gardent leur routage existant. Attention, report ou fin
de session retirent le rappel ; aucune installation n’est déclenchée par la bannière.

## Bouton de la barre d’outils

Le bouton jaune se trouvait à gauche sur macOS 27. Un espace flexible SwiftUI avant
l’action le place désormais à droite sur macOS 26 et suivants. La barre reste gérée
uniquement par SwiftUI : aucune nouvelle affectation de NSToolbar, afin de conserver
le correctif de plantage KVO livré dans la 0.2.23. Sur les systèmes antérieurs, le
placement existant reste conservé ; il n’est pas validé dans cette campagne.

## Vérifications et limites

Avant : x=96, largeur=176, marge droite=928 dans la sonde native de 1200 points.
Après : x=1016, largeur=176, marge droite=8. Quatre lancements et 640 changements
disponibilité/onboarding passent, avec une seule identité de toolbar et 256
assertions de position. Les deux vues SwiftUI livrées du bouton et des réglages
sont utilisées par les sondes, avec libellés et valeur accessibles conservés.

Le vrai flux signé public Sparkle 0.2.24 a été consulté dans une app isolée 0.2.19.
Le transport de notification injecté a accepté une seule alerte ; le routage depuis
une fenêtre fermée a rouvert le vrai panneau Sparkle et son changelog. Report,
recherche manuelle suivante et désactivation du réglage sont observés dans l’UI.
Une tentative séparée de notification système réelle a montré le refus macOS de
la sonde. Après relance avec une nouvelle identité, CUA n’a pas résolu cette app.
L’apparition d’une bannière réellement autorisée et son clic système restent donc
non validés sur ce poste. Aucun réglage de notification de l’app quotidienne n’a
été modifié. Les tests couvrent la déduplication persistante, le refus, la préférence,
la reprise après échec, l’annulation pendant l’autorisation et pendant la livraison.

373 XCTest exécutés (5 parcours optionnels ignorés, sonde mas signée active),
269 Swift Testing, build Release arm64 et 19 tests Python réussis. Une campagne
VoiceOver complète, les anciens macOS et le second Mac restent à vérifier.
Preuves locales : `build/mas-user-context-qa/`.

Source : [Sparkle — Gentle Update Reminders](https://sparkle-project.org/documentation/gentle-reminders/).


## Livraison 0.2.25 — 10 novembre 2026

**Livré dans [MacCare 0.2.25 (build 27)](https://github.com/M0okz/maccare/releases/tag/v0.2.25)**,
tag sur `c6c8483a55d6ea296b792cf564b6f0eeb40ddb1e` après fusion de la PR #34. CI de branche,
de PR, après fusion et workflow officiel réussis. Ce statut remplace les mentions
de préparation/non livré de ces changements ; les limites de validation datées
restent applicables. [Vérifications publiques et limites](release-integration-0.2.25.md).
La publication ne remplace pas les copies installées.
