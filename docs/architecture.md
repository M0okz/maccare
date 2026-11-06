# Architecture de MacCare

## Application et moteur

L’application SwiftUI conserve les modèles de chaque rubrique dans `AppState`.
Le moteur Rust expose une frontière C dans `core/include/maccare_core.h` ; Swift
utilise le module `CMacCareCore`. Les règles TOML ouvertes sont livrées dans les
ressources du paquet. Les recherches de fichiers et les suppressions sont des
opérations distinctes : un résultat d’analyse ne vaut pas autorisation de supprimer.

Le moteur prépare un plan puis revalide les éléments avant action : identité du
fichier, liens symboliques, confinement sous la racine, arbres protégés. Les tests
Rust couvrent ces contrôles et les modifications concurrentes du système de fichiers.

## Assistant privilégié

`MacCareHelper` est embarqué dans `Contents/MacOS`. Son plist launchd déclare un
`BundleProgram` relatif au paquet. SMAppService gère son enregistrement, sous
approbation explicite de l’utilisateur. Le DMG n’enregistre rien dans le système.

Le descripteur embarqué porte aussi la version, le build et le canal du paquet
dans trois variables d’environnement informatives. Ces valeurs sont préparées
avant signature ; elles distinguent la configuration d’un nouveau paquet de
celle d’un build de développement. L’identité du service, les exigences de
signature, la récupération batterie et les opérations XPC ne sont pas modifiées.

Depuis Batterie, une reprise explicite retente l’enregistrement même lorsque le
statut reste en attente d’approbation. Les refus normaux d’autorisation et le cas
déjà enregistré conduisent aux Réglages Système si le statut le demande. Une
erreur de signature demeure affichée. Un service déjà activé est seulement
interrogé : cette reprise ne le désenregistre pas et n’active pas la protection.

Le protocole XPC décrit des opérations fermées ; ce n’est pas une interface shell
arbitraire. L’assistant contrôle la signature du client et applique les contrôles
propres à chaque opération. Les opérations sensibles sont séparées de l’analyse
et des préférences d’inclusion dans un scan.

## Batterie et télémétrie

La télémétrie utilise les interfaces macOS et distingue les données indisponibles
des valeurs nulles. Le suivi CPU, mémoire et Wi-Fi est partagé entre la barre des
menus, l’accueil et les fenêtres de détails. Chaque consommateur enregistre sa
demande de suivi ; la disparition de l’un ne doit pas arrêter les autres. Une vue ne
demande le suivi que lorsqu’elle affiche des valeurs : volet ouvert, ou fenêtre visible.
Sans demande, aucun relevé n’a lieu, et les courbes repartent de zéro à la reprise.

La protection batterie est facultative et démarre désactivée. L’assistant conserve
un état de récupération et un bail surveillé ; il tente de restaurer la configuration
initiale à l’arrêt, à la veille ou à la perte de contact. Le backend dépend du Mac
et de la disponibilité des interfaces de charge. Les détails mesurés sur une
machine ne constituent pas une validation matérielle de tous les modèles.

Une méthode de politique native distincte, préparée pour la version 0.2.2, s'adresse aux
interfaces Apple récentes. Son journal v5 possède deux préférences typées et la
coupure d'adaptateur ; la configuration demandée est suivie séparément de la cible enregistrée
et de la charge physique. Voir [le contrat de cette méthode](native-charge-policy.md).
Le protocole 10 impose une mise à jour explicite du helper : restauration
confirmée de l’ancienne session, remplacement du service, puis contrôle du
protocole chargé. Cette opération ne réactive pas la protection.
La découverte standard n'active cette méthode que sur le MacBookPro17,1, seul modèle
essayé sur matériel ; les autres gardent les méthodes précédentes. Si le fichier du helper
est remplacé pendant une restauration en attente, il se termine entre deux opérations et
launchd le relance depuis le nouveau paquet, qui reprend le journal.

## Fenêtres, barre des menus et Dock

`TrayPanelController` présente un panneau natif indépendant de la fenêtre
principale. `MenuBarView` privilégie une vue compacte sans défilement et conserve
un repli pour les zones utiles trop courtes. `TrayMetricTile` partage les
proportions entre disque, mémoire, CPU et Wi-Fi ; `TrayAppearance` et
`TrayTileStyle` centralisent leurs surfaces et contrôles compacts.

`DockVisibilityController`, détenu par `AppDelegate`, choisit la présence dans le
Dock à partir des fenêtres de travail et du réglage de barre des menus. Les
panneaux de menus sont exclus ; les fenêtres minimisées restent restaurables
par le Dock. Les actions qui ouvrent une fenêtre rétablissent la politique
AppKit `regular` avant activation. Voir [le comportement et ses validations](menu-bar-panel.md).

## Indicateurs système du volet

`TrayMetricsSampler` lit la pression mémoire XNU et relève la température CPU
hors du fil principal (cache de 5 secondes). Le pont C `maccare_cpu_temperature`
ne fait que des lectures IOHID/SMC ; les fonctions existantes de contrôle batterie
et le protocole de l’assistant ne changent pas.

`NetworkInterfaceSample` associe type, adresse et compteurs à la route principale
SystemConfiguration, IPv4 puis IPv6. `TrayMetrics.Network` porte cette identité ;
les noms historiques `wifi` restent compatibles. Le lissage et l’historique
réinitialisent les débits lors d’un changement d’interface ou d’IP. Les unités de
présentation sont centralisées par `NetworkRateFormat`. La grille `TrayStorageGrid`
est une projection arrondie de l’espace utilisé sur 72 cellules, indépendante
de la lecture des capacités. [Origines, contrôles et limites](menu-bar-panel.md).

## Santé et contexte de batterie

`MacHealthScore` est un calcul pur pondéré, indépendant des vues : stockage,
pression mémoire, état thermique et capacité batterie. Les absences de données
et les plafonds critiques sont explicites. `MacHealthDetails` expose le calcul,
et `MacSystemSpecs` centralise les caractéristiques du Mac et sa date de démarrage.

`TrayBatteryController` possède le suivi limité à la vie du volet ; son acteur
lit le chargeur/accessoires IOPS et les processus. `TrayProcessSampler` peut
relever l’énergie attribuée par macOS sans changer les actions de fermeture.
La puissance vient des nanojoules ; le repli CPU est explicitement séparé et
conserve la base de temps Mach. [Barème et limites](menu-bar-panel.md).

## Distribution

L’app et l’assistant conservent des identifiants distincts, avec une signature Apple
cohérente. Le paquet de distribution utilise le runtime durci ; l’app déclare son
entitlement d’Automatisation pour System Events. Sparkle est embarqué dans Frameworks
et ses composants imbriqués sont signés avant l’app.

Sparkle vérifie un flux public signé et la signature du DMG final avant extraction.
Les recherches automatiques sont désactivables et les installations nécessitent
une action de l’utilisateur. Les détails et limites de validation sont dans
[la procédure de release](releasing.md).


### Volet GPU/ventilateurs et raccourcis — 6 novembre 2026, non livré

`TrayMetricsSampler` relève IOAccelerator (GPU le plus actif, modèle/cœurs/charge),
les capteurs HID GPU et les clés SMC de vitesse des ventilateurs. Les mesures
restent dans l’actor, températures et ventilateurs en cache de cinq secondes,
charge GPU à la cadence de suivi existante. `TrayGPUHistory` conserve 40 secondes
et réinitialise l’historique lors d’un changement de GPU. Aucun appel de commande
ventilateur ajouté. Données manquantes distinctes des zéros mesurés ; bornes et
types contrôlés. L’absence de capteur GPU compatible reste explicite.

`TrayShortcuts` partage le contrat de préférence entre `MenuBarView` et
`TrayShortcutSettingsView` dans les réglages blancs. Quatre positions, liste
fermée de modules, Aucun, déduplication et validation à la lecture. Les boutons
appellent la navigation existante, sans exécuter d’entretien. L’en-tête masque
le pourcentage du score ; son calcul explicable reste accessible. La carte
batterie est conservée. Référence vérifiée : `main` à `134b7bc`, modifications
de travail, `build/tray-layout/MacCare.app`, 53 tests ciblés, neuf assertions
C, signature et rendu natif. Limites détaillées dans `menu-bar-panel.md`.


### Publication du volet compact — 6 novembre 2026

Les ajouts du volet décrits dans les sections précédentes sont publiés en
0.2.10 (build 12), tag `v0.2.10` sur `e5dfb42` (PR #17, source `a48bedf`).
La branche `codex/compact-menu-bar` est supprimée après CI verte. Les mesures
restent en lecture seule et à la demande ; aucun réglage ventilateur ajouté.
Le DMG public et le flux Sparkle ont été vérifiés, sans remplacer la copie
quotidienne en 0.2.8 (10). Contrôles et limites dans `menu-bar-panel.md`.

### Popovers Stockage et Batterie — correction Dev du 6 novembre 2026

`TrayDetailSelection` sépare les détails d’activité existants (`TrayMetricDetail.Kind`)
et les nouveaux détails Stockage/Batterie. Une sélection unique pilote le popover
du volet ; les outils complets restent accessibles par une action de navigation
explicite. `TrayDetailSurface` mutualise le cadre violet sans modifier le suivi des
processus CPU/mémoire. `TrayStorageUsage` normalise les volumes, `TrayStorageDetail`
réutilise le relevé disque du parent et `TrayBatteryDetail` observe le modèle batterie
et la télémétrie déjà suivis. Pas de nouvelle analyse, boucle de suivi, écriture de
charge ou commande ventilateur. Correction locale après 0.2.10, non publiée ; branche
`codex/tray-storage-battery-details`, base `ec8cca3`.

### Retour à la préparation du nettoyage — correction Dev du 6 novembre 2026

Le bouton de relance du bilan distingue `CleaningOverviewView.prepareNewAnalysis()`
du démarrage réel `analyze()`. Il appelle `SmartScanModel.prepareForNewScan()` et
retire le mode d’accès direct aux outils. Le modèle annule le scan, incrémente sa
génération et efface l’état de la session, tout en gardant le dernier bilan complet
mémorisé. La remise à zéro est refusée pendant une suppression. UserDefaults devient
injectable pour des tests isolés ; les clés et le domaine utilisés en production
ne changent pas. Régression avant/après : `CleaningRestartTests`, complétée par
Nettoyage/profils/navigation (15 tests). Aucun changement du moteur Rust ni de la
politique de suppression. Correction locale non publiée ; voir cleaning-managers.

### Recommencer les bilans — correction Dev du 6 novembre 2026

Performances et Applications distinguent également le retour à la préparation
du lancement d’une analyse. Le premier remet `performanceAnalyzed` à faux ; le
second appelle `ApplicationsAnalysisModel.prepareForNewAnalysis()`. Les deux
retirent leur détail actif et refusent le retour pendant une opération en cours.
Les inventaires déjà lus restent disponibles aux outils. Mes fichiers conserve
son retour au choix du dossier ; Espace disque conserve la distinction entre
Changer d’emplacement et Actualiser la mesure. Voir [les validations Dev et
limites](analysis-restarts.md). Aucun changement du moteur ni de la suppression.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).
