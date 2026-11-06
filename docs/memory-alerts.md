# Alerte de mémoire

Disponible depuis [MacCare 0.2.8 (build 10)](https://github.com/M0okz/maccare/releases/tag/v0.2.8), publiée le 6 novembre 2026
(heure de Paris). Installation de cette version vérifiée dans
`/Applications/MacCare.app` via Sparkle, depuis 0.2.6 (8). Le paquet installé
correspond au binaire public signé et notarié. Les validations de développement
ci-dessous restent datées et conservent leurs limites.

Historique de développement : branche `codex/menu-bar-alerts`, mise à jour
sur la base 0.2.5 avant intégration dans la PR nº 4.

L’alerte reprend le panneau de l’alerte disque : largeur de 340 points,
pointe ancrée sous l’icône MacCare, un seul flou AppKit natif et un trait
sombre de 1 point. Les apparences claire et sombre suivent macOS. Le panneau
ne prend pas le premier plan et se ferme avec Échap ou un clic extérieur.

## Déclenchement et rappels

`MemoryPressureLevel` lit le sysctl en lecture seule
`kern.memorystatus_vm_pressure_level`. XNU exporte les flags Dispatch
(1 normal, 2 warning, 4 critical), et non les valeurs de son enum interne.
Référence : [implémentation Apple](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c).

Un warning doit persister 30 secondes ; un état critique est éligible dès
la prochaine vérification. Un relevé normal ou indisponible réinitialise
l’observation. Aucun seuil de pourcentage de RAM « utilisée » n’est employé.
Première vérification après une minute, puis toutes les 15 secondes tant
que la barre des menus et l’option sont actives. Une veille suspend le suivi.

L’alerte attend la fin de la configuration initiale, ne s’affiche pas lorsque
MacCare est au premier plan, pendant un Smart Scan/nettoyage Smart Scan ou
au-dessus du grand volet ou d’une alerte disque. Aucun parcours ne ferme
une application automatiquement. Un rappel au maximum toutes les 24 heures ;
les reports d’une journée/semaine persistent dans des préférences propres à
l’alerte mémoire (`memoryAlert.enabled`, `.lastShown`, `.snoozedUntil`).

## Applications proposées et fermetures

Jusqu’à trois applications graphiques, appartenant au compte courant et
ayant une empreinte physique d’au moins 512 Mo, sont triées par consommation
décroissante. La mesure concerne leur processus principal, mémoire compressée
comprise ; les processus auxiliaires ne sont pas agrégés. La valeur expose
cette portée dans son aide. Les processus système, les applications en
arrière-plan sans interface régulière et toutes les copies MacCare sont exclus.

« Quitter » demande une fermeture normale ; l’app peut proposer de sauvegarder
ses documents. « Tout forcer à quitter » demande une confirmation qui nomme
les seules applications affichées et précise la perte possible des modifications
non enregistrées. Il reste possible de forcer une fermeture déjà demandée
normalement. Les refus et identités obsolètes sont signalés. « Quitter » est
l’action visible de chaque ligne ; l’arrêt forcé, qui peut faire perdre du
travail, reste au second plan et sans raccourci clavier.

Avant chaque demande, le PID, la date de démarrage, l’utilisateur, le chemin
exécutable, le bundle et le caractère graphique sont revérifiés. Le chemin
existant `TrayProcessController` exécute ensuite la demande et revérifie
l’identité. Aucun service privilégié ni autorisation nouvelle n’est nécessaire.

Réglages > Barre des menus contient l’interrupteur et l’aperçu fictif.
L’aperçu Helium à 1,43 Go ne ferme rien et ne modifie aucun rappel réel.

## Composants et validation

`MemoryPressureLevel`, `MemoryAlertPolicy`, `MemoryAlertApplication`,
`MemoryAlertCandidate`, `MemoryAlertModel`, `MemoryAlertController`,
`MemoryAlertView` et `MemoryAlertSettingsView` portent la fonctionnalité.
`MenuBarAlertPresenter` partage la présentation avec `StorageAlertController`
et réutilise la surface native déjà validée (`StorageAlertPanel`,
`StorageAlertOutlineView`, `StorageAlertPrimaryButtonStyle`). Le contrôleur
de barre des menus coordonne visibilité, veille, écrans et arrêt.

Les 22 tests ciblés passent : neuf tests mémoire (flags, pression persistante,
reports, classement, identités obsolètes, portée des actions et aperçu), cinq
tests disque, quatre de disposition et quatre de processus. Ces derniers
utilisent uniquement des processus jetables créés par les tests.

La QA dans un hôte isolé a vérifié les deux apparences, le contour, la
régression visuelle de l’alerte disque, la présence des commandes dans l’arbre
d’accessibilité, la confirmation de l’arrêt forcé, son annulation et l’absence
de fermeture dans l’aperçu. Captures et journaux : `build/memory-alert-validation/`.
Une campagne VoiceOver complète, un véritable épisode critique et un cycle
matériel veille/réveil restent à tester ; aucune application de travail de
Gregory n’a été fermée pour cette QA.

Build Release et packaging `build/development/MacCare.app` réussis ; signature
Apple Development stricte, plist et `git diff --check` validés. L’empreinte
binaire de la version quotidienne 0.2.1 (3) est restée identique.

Après report sur la base 0.2.1, le 4 novembre : suite Swift complète réussie
(181 tests XCTest et 92 tests Swift Testing), 15 tests de release, build Release
et paquet `build/development/MacCare.app` 0.2.1 à signature stricte valide. La QA
visuelle en hôte isolé n’a pas été rejouée sur cette base.

Après fusion de `main` en version 0.2.5, le 5 novembre : suite Swift complète
réussie (186 tests XCTest et 226 tests Swift Testing), 15 tests de release, build
Release et paquet 0.2.5 à signature stricte valide. La QA visuelle n’a pas non
plus été rejouée sur cette base.

Documentation Outline synchronisée et relue le 4 novembre : index et chapitres
02, 03, 04, 06, 08 et 11, en conservant les descriptions des versions livrées.
Cette synchronisation couvre également l’alerte disque précédemment en attente.
