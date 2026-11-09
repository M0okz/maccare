# Architecture de MacCare

## Lecture des appareils jumelés — développement du 9 novembre 2026

**Non livré.** `MacCareDeviceBatteryProbe` est un exécutable utilisateur ponctuel,
distinct du service privilégié. Il charge MobileDevice optionnellement et lit
les seuls appareils déjà approuvés ; aucune commande de jumelage, de réglage
Wi-Fi ou de contrôle de charge. Délais 4 s dans la sonde / 5 s dans le parent.
Un acteur partage son acquisition entre les cartes visibles, avec cache RAM et
espacement des échecs. Lecture USB iPhone/Watch vérifiée ; Wi-Fi et consommation
prolongée restent à tester. Un canal compagnon est ouvert par requête.
Voir [la frontière et ses validations](apple-device-batteries.md).

## Désinstallation — MacCare 0.2.16

**Livré dans [MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16).** `Remover.uninstall` traite le paquet choisi dans son dossier Applications avec une liste d’inclusion, puis ses données dans le dossier personnel. Le nettoyage générique reste inchangé. Le modèle agrège les comptes rendus et retire les paquets disparus du catalogue.

Voir [le contrat, les tests et les limites](application-removal.md).

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

## Source App Store autonome

`UpdatesModel` délègue à `AppStoreUpdates` la vérification en lecture seule par
`Contents/Helpers/mas` (7.0.0). Ce composant est figé, vérifié, signé et embarqué
par le packaging ; sa détection ne dépend pas de Homebrew. Les résultats JSON
rejoignent le gestionnaire Applications et ouvrent l'App Store pour installer
à la demande. Voir [le contrat et les limites](app-store-updates.md).

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

La télémétrie distingue les données indisponibles des valeurs nulles. Le suivi
CPU/GPU, mémoire et réseau est partagé entre le volet, l’accueil et les détails.
**Depuis MacCare 0.2.16** : `TrayMetricsStore` garde une
seule boucle à une seconde avec une vue visible, cinq secondes sans vue visible.
Les capteurs SMC/HID et CoreWLAN ne sont pas relus en arrière-plan. La navigation
change la cadence sans réamorcer les compteurs. Le store conserve une heure en
groupes de cinq secondes (moyenne et maximum), dix minutes dans les cartes.
Les tracés relient les relevés réels sans coupure visuelle ; la veille suspend
la collecte et n’ajoute ni mesure ni volume fictif. La version 0.2.15
utilisait l’arrêt des relevés hors visibilité. Voir [le cycle de vie,
les bornes mémoire et les limites](activity-metrics-cache.md).

Depuis MacCare 0.2.15, la température GPU possède aussi un repli SMC borné aux
capteurs GPU connus de la famille M1 si HID n’en fournit aucun. Le cache de cinq
secondes reste inchangé. Voir [les tests et limites matérielles](gpu-temperature-m1.md).

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

`TrayBatteryController` possède le suivi limité à la visibilité du volet ou de la
carte Batterie de l’accueil ; son acteur
lit le chargeur/accessoires IOPS et les processus. `TrayProcessSampler` peut
relever l’énergie attribuée par macOS sans changer les actions de fermeture.
La puissance vient des nanojoules ; le repli CPU est explicitement séparé et
conserve la base de temps Mach. [Barème et limites](menu-bar-panel.md).

## Cartes de l’accueil — développement après 0.2.11

`HomeCleaningCard` projette une répartition des seuls groupes sûrs. Le calcul pur
`HomeCleaningBreakdown` est mémorisé par `SmartScanModel` avec date et total du
bilan ; une répartition absente ou incohérente n’est pas reconstruite arbitrairement.
L’action Analyser prépare un nouveau bilan, sans relancer immédiatement le moteur.

`HomeBatteryCard` réutilise les relevés du volet pour les anneaux d’accessoires,
le chargeur en watts et le processus énergivore. `HomeActivityCard` compose six
tuiles : CPU, GPU, mémoire, stockage, réseau et ventilateurs. Les mesures et
historiques viennent du store partagé ; le stockage reprend le relevé de l’accueil.
Les composants n’ajoutent pas de lecteurs matériels ni de commandes de charge ou
de vitesse. [Données, disposition et validations](dashboard-cards.md).

`TrayBatteryAccessoryHistory` conserve les derniers niveaux connus pendant
20 secondes au plus depuis la dernière lecture de chaque appareil. Le contrôleur
stabilise leur ordre et leur identité de présentation malgré les relevés partiels
ou les changements de numéro de source. Chargeur et accessoires restent mis à jour
à chaque relevé de 5 secondes. Depuis la version 0.2.14, `TrayBatteryProcessCadence` limite les
lectures de processus à 15 secondes après l’amorçage initial ; le sampler conserve
la dernière mesure entre ces lectures. La validité des deltas est bornée à
30 secondes pour ce sampler, sans changer le seuil par défaut des listes rapides.
MacCare et ses auxiliaires sont exclus du classement batterie et de son repli CPU.
La carte d’accueil réserve une zone fixe à trois accessoires au maximum, sans
anneau du Mac, avec les détails au survol et accessibles. Son processus est une
ligne unique icône/nom/valeur. [État Dev et validations](dashboard-cards.md).

La disposition d’accueil validée retire la carte disque autonome : un seul
`HomeCleaningCard` occupe la première ligne, puis `HomeStatusCards` compose
Batterie/Santé dans une colonne et Activité en regard. `HomeHealthPresentation`
résume les signaux existants sans recalculer un autre indice : il conserve
l’évaluation `MacHealthScore`, réutilise le seuil d’alerte stockage et priorise les
conditions critiques. Les plafonds chiffrés restent dans `MacHealthDetails`, pas
dans la raison courte de la carte. `HomeHealthCard` observe le store et le modèle
batterie existants ; son uptime se met à jour à la minute sans nouveau lecteur
matériel. Les dispositions étroites passent par `ViewThatFits` et l’empilement.
Le remplissage vertical du style est explicite pour Activité ; Batterie et Santé
conservent leur hauteur de contenu, avec alimentation/puissance et caractéristiques/
uptime regroupés pour éviter l’étirement des tuiles.

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


## PNG natifs et diagnostic des disques — Dev du 7 novembre 2026

oxipng 10.2.1 est lié au moteur Rust via une frontière C/JSON pour créer des copies
PNG sans écrasement depuis Mes fichiers. smartctl 7.5 est embarqué, signé et utilisé
en lecture seule dans Outils → Santé des disques et le sous-volet Stockage interne
de la barre des menus. La section Espace disque reste distincte. Détails, bornes,
licences et vérifications : [outils natifs](native-file-disk-tools.md).

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.

## Disposition par écran — développement après 0.2.12

`MainWindowDisplayObserver` publie une politique `MainWindowLayout` à partir de
l’espace visible en points de l’écran de la fenêtre principale. `RootView`
conserve cette valeur locale ; `DisplayAdjustedContent` adapte proposition de
taille et rendu ensemble. `WindowConfigurator` réutilise cette politique pour
la taille initiale et une réduction unique des grandes fenêtres restaurées.
Les modèles globaux et les autres fenêtres restent indépendants. L’aperçu
compact est réservé aux paquets Dev. Voir [les seuils et la validation](display-layout.md).

## Publication 0.2.13 — 8 novembre 2026

Cette adaptation est publiée dans [MacCare 0.2.13 (build 15)](https://github.com/M0okz/maccare/releases/tag/v0.2.13), tag `v0.2.13` sur `9a9dc5612dd9bf6b02c9438c3e721f2ca85efb2b`, après fusion de la [PR #20](https://github.com/M0okz/maccare/pull/20). La branche `codex/compact-interface` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des notes précédentes ; les validations datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42512588574) est réussi, comme les CI de branche, de PR et de fusion. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, notarisation et tickets app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; le flux latest correspond à la release. DMG : 15944980 octets, SHA-256 `0b790855ba2803ada5d33b1cea43c156bdc39dfebcc63719a6a9241c282e2a04`. Le site public propose ce paquet avec les mêmes taille et empreinte ; son HTML correspond aux sources et le conteneur est sain.

Le rendu sur le MacBook Pro 14 pouces en « Plus d’espace » reste à confirmer physiquement ; le format réduit cible a été testé par géométrie, l’aperçu compact étant observé dans une fenêtre plus grande. Pas de validation réelle de déplacement entre écrans ni de campagne complète d’accessibilité. Aucune installation quotidienne effectuée : la copie quotidienne et la Dev 0.2.13 (3) sont préservées. L’application de distribution n’a pas été lancée dans cette livraison. Preuves : `build/release-0.2.13-qa/`.

## Navigation et commandes de fenêtre — Dev du 8 novembre 2026

`Sidebar` sépare le groupe principal défilable du pied Mes outils. Les routes de
`NavigationSection.primary` restent complètes ; tools est filtré uniquement de
la liste visuelle supérieure et dessiné une fois dans le pied. Son titre est
centralisé pour la navigation et la page dédiée. `WindowConfigurator.Coordinator`
conserve les dimensions originales des boutons AppKit et ajuste leurs cadres,
sans changer leurs cibles/actions. Le coordinateur appartient à la fenêtre
principale ; les autres surfaces gardent leur configuration. [Détails et limites](sidebar-spacing.md).

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.

## Icônes des helpers — développement après 0.2.14

`TrayProcessController` délègue la résolution à `TrayProcessIconResolver` sur
l’acteur principal. Le paquet application extérieur est déterminé depuis le
chemin de l’exécutable ou le paquet enregistré auprès de macOS. Son icône sert
aux helpers ; les vrais services système sans application restent génériques.
Le cache par identité PID/démarrage, les noms et les actions sont conservés.
[Contrats, vérifications et limites](process-icons.md). Travail non publié.

## Retour aux boutons AppKit natifs — Dev du 8 novembre 2026

Le coordinateur de `WindowConfigurator` qui forçait les tailles et espacements
des boutons de fenêtre est supprimé. Le configurateur conserve uniquement son
rôle antérieur de barre de titre et de disposition de la fenêtre ; AppKit gère
les boutons standard. La navigation aérée et le correctif d’icônes de helpers
restent en place. Correctif Dev non publié sur `codex/helper-process-icons` ;
[état et validations](sidebar-spacing.md).

## Carte Espace disque — interactions du 9 novembre 2026

`SpaceBubblesView` possède un seul suivi du pointeur dans les coordonnées de la
carte. `BubbleHitTest` utilise les centres/rayons fournis par `BubblePacker` ;
le chemin de survol est partagé avec la liste et publié seulement à son changement.
`SpaceModel.HoverSource` identifie la carte ou la ligne qui possède ce survol ;
les événements de sortie des anciennes sources sont ignorés.
Les boutons sont sensibles au cercle, sélectionnent au clic simple et ouvrent
les dossiers au double-clic ; leur action d’accessibilité garde l’ouverture directe.
Voir [les comportements et preuves Dev](space-bubbles-interaction.md).
