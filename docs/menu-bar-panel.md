# Volet compact et présence dans le Dock

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

## Température GPU M1 — Dev du 9 novembre 2026

Après le signalement d’une température absente sur M1 Max, la lecture GPU HID
dispose d’un repli SMC pour les quatre capteurs connus de la famille M1.
Le cache de cinq secondes et le suivi lié à la visibilité restent inchangés.
Voir [les tests et la limite de validation sur M1 Max](gpu-temperature-m1.md).

## Cache des mesures — Dev du 8 novembre 2026

La fermeture du volet suspend le suivi lorsqu’aucune autre vue visible ne le
demande, tout en gardant les valeurs et courbes dans le store partagé. La reprise
amorce les compteurs et distingue les pauses des périodes réellement observées.
Voir [le fonctionnement et les limites](activity-metrics-cache.md).

## État au 6 novembre 2026

Le volet décrit ici est publié dans [MacCare 0.2.10 (build 12)](https://github.com/M0okz/maccare/releases/tag/v0.2.10),
à partir du tag `v0.2.10` sur `e5dfb42` (PR #17, commit fonctionnel `a48bedf`).
Le paquet public Developer ID arm64 est signé et notarié ; les signatures du DMG
et du flux Sparkle ont été vérifiées avec la clé publique de la copie installée.
Le paquet Dev de QA est `build/tray-layout/MacCare.app`, identifié **MacCare Dev**.
La copie quotidienne `/Applications/MacCare.app` reste en 0.2.8 (10), sans remplacement.

## Vue d’ensemble

Le volet conserve son identité violette. La première passe réduisait seulement
les grands blocs et l’enveloppe (540 × 534 points) ; la passe de densité reprend
les proportions internes (420 × 430 points). L’ajout des informations réseau
et de la grille de stockage porte le volet enrichi à 420 × 454 points. L’en-tête de santé et la carte batterie portent
le volet de cette passe à 420 × 560 points. La grille CPU/GPU, mémoire/ventilateurs
et stockage/réseau tient désormais dans 420 × 590 points, dont 44
pour le pied de volet ; les éléments restent à leur échelle compacte.

| Élément | Première passe | Densité actuelle |
| --- | --- | --- |
| Valeurs disque, mémoire, CPU, Wi-Fi | 23–25 pt | 18 pt, avec `ScaledMetric` |
| Cartes de mesures | 88–92 pt environ | 84 pt, informations supplémentaires incluses |
| Jauge mémoire | 45 pt, trait de 6 pt | 28 pt, trait de 3 pt |
| Boutons | 36–38 pt | 28 pt |
| Marges des cartes | 10 pt | 8 pt |
| Espacement de grille | 8 pt | 6 pt |

`TrayMetricTile` partage la même hiérarchie entre les six mesures : titre,
valeur, détail, indicateur secondaire. `TrayAppearance` centralise les couleurs
et rayons, et `TrayTileStyle` sert aussi à la batterie. Les boutons gardent leur
retour de pression ; aucune animation décorative n’est ajoutée. Les débits réseau
utilisent deux colonnes de largeur constante pour éviter de décaler l’envoi à
chaque changement de longueur du débit reçu.

- L’en-tête affiche « Santé du Mac » et le palier sans pourcentage, puis le nom
  du Mac. Une seule ligne réunit RAM, stockage interne, macOS et uptime
  (temps de veille compris). Une aide donne les libellés complets. Cliquer
  sur la santé ouvre toujours le calcul et son pourcentage détaillé.
- Smart Scan réunit le dernier bilan, l’espace récupérable et l’action d’analyse
  dans un bandeau compact. Les états analyse/nettoyage et leurs actions restent accessibles.
- « Stockage interne » conserve l’espace disponible et la capacité totale. Une
  grille de **6 lignes × 12 colonnes** remplace la barre : les 72 carrés de 4 points
  sont remplis selon la fraction utilisée, arrondie au carré le plus proche.
- Mémoire conserve le pourcentage d’utilisation et affiche en plus la pression
  réelle de macOS : normale, élevée ou critique. Ces deux données sont distinctes.
- Processeur conserve la charge et l’historique ; la température CPU est affichée
  à droite de la valeur lorsque la lecture des capteurs est disponible.
- GPU affiche la charge, la température des capteurs GPU disponibles, un historique
  de 40 secondes et le nombre de cœurs du GPU observé.
- Ventilateurs affiche la vitesse la plus élevée en tr/min, la fraction de vitesse
  maximale si connue et un état explicite. L’aide détaille chaque ventilateur.
  La surveillance ne modifie aucune vitesse ni aucun mode.
- « Réseau » indique le type de connexion, l’adresse IP locale et les débits
  réception/envoi en Mb/s. Les cartes restent dans une grille de deux colonnes.
- La batterie, sur les Mac qui en disposent, affiche charge, capacité restante
  estimée, source d’alimentation, autonomie ou puissance annoncée du chargeur,
  jauge du Mac et jusqu’à deux accessoires réellement signalés par macOS.
  La protection active garde un pictogramme et son message d’aide. La ligne
  inférieure identifie le processus le plus énergivore parmi ceux accessibles,
  ou un repli explicitement nommé « Plus actif CPU ».
- Le pied de volet réunit jusqu’à quatre raccourcis d’outils, puis les icônes
  « Ouvrir MacCare » et « Réglages de MacCare ». Plus et Quitter sont retirés
  du volet. Chaque icône possède un nom accessible et une aide au survol.
- Réglages → Menu → Raccourcis du volet propose quatre positions ordonnées et
  le choix « Aucun ». La préférence `tray.toolShortcuts` conserve quatre identifiants
  de modules séparés par des virgules (vides autorisés). Les inconnus et doublons
  sont ignorés ; sélectionner un outil déjà choisi le déplace dans la position
  demandée. Défauts : Nettoyage, Performances, Espace disque et Maintenance.
  Les raccourcis ouvrent l’outil et ne lancent pas son action.

`ViewThatFits` choisit la vue sans défilement lorsqu’elle tient dans l’espace
utile ; une vue défilante reste disponible pour les écrans exceptionnellement
courts. Le panneau reste borné à la zone utile de l’écran. La cadence des mesures
et celle de l’affichage réseau ne changent pas.

## Dock et fenêtres

Avec la barre des menus activée, la fermeture de la dernière fenêtre de travail
bascule l’application en politique AppKit `accessory` : le processus et la barre
restent actifs, l’icône du Dock disparaît. Le volet et ses popovers ne comptent pas
comme fenêtres de travail. Une autre fenêtre visible ou une fenêtre minimisée
conserve le Dock ; sans barre des menus, la fermeture de la dernière fenêtre
conserve le comportement de sortie existant.

`DockVisibilityController`, détenu par `AppDelegate`, observe l’ouverture et la
fermeture des fenêtres ainsi que les changements de préférences. La fenêtre en
cours de fermeture est exclue du calcul avant que macOS la retire de sa liste.
Les actions d’ouverture de la fenêtre principale, d’une rubrique et des réglages
rétablissent la politique `regular` avant l’activation de l’application.

## Vérifications

- Build Release et signature profonde stricte du paquet Dev réussis ; plist valide.
- 47 XCTest ciblés passent sur cette passe : santé, télémétrie batterie, énergie,
  processus, géométrie, métriques et Dock. Les vérifications précédentes des
  indicateurs sont conservées dans les preuves datées du même jour.
- Observation native du paquet : les cinq indicateurs et les actions sont visibles
  dans le volet de 420 × 560 points, sans zone de défilement dans l’arbre accessible.
  Le détail mémoire s’ouvre et se ferme avec Échap. Le menu « Plus » contient
  « Vérifier le système ».
- Reproduction avant correction : aucune fenêtre à l’écran et processus encore
  en politique `regular`. Après correction : `accessory` à la fermeture, puis
  `regular` à la réouverture, sur le même processus de développement.
- SHA-256 de l’exécutable utilisateur inchangé :
  `78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.

Les tests de politique couvrent aussi plusieurs fenêtres, une fenêtre minimisée,
le volet exclu et la barre des menus désactivée. Ces scénarios supplémentaires
n’ont pas tous été rejoués visuellement. Le lancement à la connexion, VoiceOver,
la navigation intégralement au clavier et les réglages d’accessibilité système
n’ont pas été validés pendant cette intervention. Aucun contrôle matériel de la
charge n’est inclus dans cette évolution. Le paquet de densité a été lancé avec
`-battery.protection.resume NO` pour ne pas reprendre automatiquement la protection
depuis cette copie de développement.

## Origine des nouveaux indicateurs — 6 novembre 2026

`NetworkInterfaceSample` lit `PrimaryInterface` dans l’état global IPv4 de
SystemConfiguration, ou IPv6 à défaut. L’adresse et les compteurs sont lus sur
cette interface avec `getifaddrs`. Les autres interfaces ne sont pas additionnées.
Le type repose sur CoreWLAN/SystemConfiguration, avec les préfixes connus des
interfaces VPN. L’IP est locale : aucune requête externe ne cherche l’IP publique.
Une IPv6 longue peut être abrégée au milieu, avec sa valeur complète dans l’aide.
Un VPN à routage partagé ne devient donc pas le type affiché lorsqu’il ne porte
pas la route principale. Un réseau local sans route principale reste indisponible.

Les compteurs sont convertis en mégabits décimaux : octets/s × 8 / 1 000 000.
La petite carte garde sa cadence de 3 secondes ; type, adresse et changements
d’interface sont rafraîchis immédiatement au relevé suivant. Le détail conserve
sa cadence normale. L’historique et le lissage redémarrent lors d’un changement
d’identité réseau, pour ne pas mêler les anciens compteurs au nouveau lien.
L’accueil et le détail réseau utilisent aussi l’interface active et les Mb/s.
Les noms internes historiques `wifi`, `WiFiTrafficHistory` et `TrayWiFiDetail`
restent compatibles, mais le modèle `TrayMetrics.Network` n’est plus limité au Wi-Fi.

La pression provient de `MemoryPressureLevel.current()` : niveaux système XNU
1/2/4, sans transformer le pourcentage de RAM utilisée en faux pourcentage de
pression. `TrayMetricsSmoothing` conserve cette information immédiatement.

La température est le maximum des capteurs CPU disponibles, relevé toutes les
5 secondes hors du fil d’interface. Sur Apple Silicon, le lecteur C utilise les
événements IOHID des services CPU `pACC MTR Temp` et `eACC MTR Temp` uniquement.
Il charge les symboles dynamiquement et conserve un repli de lecture de clés SMC
CPU connues sur M1/Intel ; absence de capteur, refus ou format inconnu donnent
une valeur indisponible. Aucun capteur GPU, SoC générique ou batterie ne remplace
silencieusement un capteur CPU. Aucun appel d’écriture matériel n’est ajouté,
aucune permission ni mise à jour du service privilégié n’est nécessaire pour la
lecture IOHID observée sur le M1.

Références primaires :
[propriété PrimaryInterface d’Apple](https://developer.apple.com/documentation/systemconfiguration/kscdynamicstorepropnetprimaryinterface-swift.var),
[lecture IOHID de Stats](https://github.com/exelban/stats/blob/master/Modules/Sensors/reader.m),
[identités des capteurs](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift).
Les signatures et identités servent de référence ; MacCare conserve son lecteur
fermé en lecture seule, sans dépendance à Stats.

Validation native sur le MacBook Pro M1 : 67 carrés occupés sur 72 observés,
pression mémoire élevée effectivement remontée par le système, température CPU
mesurée et évoluant au fil des relevés, type Wi-Fi et IP locale présents, débits
en Mb/s dans le volet et son détail. Les détails Réseau et Mémoire ont été
ouverts et refermés par Échap. Aucun test de vitesse Internet n’a été lancé.
Les cas Ethernet, VPN, IPv6 seul et pression critique sont couverts partiellement
par les fixtures, sans changement réel de connexion ou de pression provoqué.
Les autres modèles de Mac et le repli Intel/SMC ne sont pas validés matériellement.

## Indice de santé et batterie enrichie — 6 novembre 2026

La santé est un **indice estimé de l’état actuel**, explicable dans un détail
cliquable ; ce n’est pas un diagnostic matériel complet. Ni l’utilisation CPU
instantanée, ni un long uptime, ni des fichiers récupérables lors d’un scan ne
font baisser la note. Le pourcentage de charge de la batterie ne remplace pas
sa capacité restante estimée.

| Critère | Poids | Calcul |
| --- | --- | --- |
| Stockage | 30 | Disponible / réserve, borné à 0–1 ; réserve = min(15 % du volume, 50 Go) |
| Pression mémoire | 30 | Normale = 100 %, élevée = 60 %, critique = 10 % des points |
| État thermique macOS | 25 | Normal = 100 %, modéré = 75 %, élevé = 35 %, critique = 0 % des points |
| Batterie | 15 | Capacité restante estimée / 100 ; non applicable sans batterie |

La somme est normalisée sur les poids disponibles, puis arrondie. Mauvais :
0–49 % ; Bien : 50–84 % ; Excellent : 85–100 %. Des plafonds empêchent un problème
critique d’être masqué : moins de 2 % libres **et** moins de 5 Go → 45 % ; pression
critique → 40 % ; thermique élevé → 49 %, critique → 25 % ; défaut batterie →
35 % ; capacité batterie sous 60 % ou état macOS à vérifier → 49 % ; capacité de
60 à 79 % → 84 %. Le plafond le plus bas s’applique.

Sans espace disponible, pression ou état thermique fiables, le score reste en
calcul et ne publie pas de pourcentage. Sans donnée de capacité batterie alors
qu’elle est présente ou en attente de lecture, il est explicitement partiel et
plafonné à 84 %. Sur un Mac sans batterie, les trois critères applicables sont
normalisés sans pénalité fictive. `MacHealthScore` isole ce barème des vues ;
`MacHealthDetails` montre chaque contribution et les éventuels plafonds.

`MacSystemSpecs` lit la RAM physique, la version macOS et la date `kern.boottime`.
La capacité indiquée est celle du volume interne observé, pas une capacité SSD
commerciale inventée. L’uptime inclut la veille et n’affiche pas de durée négative.

`TrayBatterySampler` lit la puissance annoncée de l’adaptateur par IOPS, sans la
présenter comme la consommation du Mac. Les accessoires proviennent des sources
accessoires IOPS déjà signalées, avec un repli sur les services HID présents ;
aucune recherche Bluetooth, aucun appairage ni anneau fictif pour un téléphone
ou des écouteurs absents. Les niveaux manquants/incohérents sont ignorés.
L’API accessoires optionnelle est chargée dynamiquement et ne bloque pas le volet
si elle est absente. Référence ABI :
[IOPowerSourcesPrivate.h d’Apple](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPowerSourcesPrivate.h).

La ligne « Plus énergivore » vient de deux relevés des compteurs
`rusage_info_v6.ri_energy_nj` : delta nanojoules / 1 milliard / secondes, en watts
attribués par macOS aux processus accessibles. Si ces compteurs ne sont pas
exploitables, le libellé devient « Plus actif CPU » et utilise un pourcentage de
cœur, sans se faire passer pour une mesure d’énergie. Les compteurs CPU gardent
la base de temps Mach propre à l’hôte, vérifiée sur un processus de test réellement
occupé. PID et date de démarrage évitent de mêler deux incarnations d’un processus ;
compteur réinitialisé, intervalle invalide ou trop long → mesure absente.
Les très petites puissances s’affichent « < 0,01 W » plutôt qu’un faux zéro.

Le contrôleur ne suit les processus et accessoires que pendant l’affichage du
volet avec une batterie présente : premier intervalle de 1 s pour obtenir le
delta, puis 5 s. Les tâches sont annulées au démontage du volet. Aucune commande
de contrôle de charge n’est ajoutée. Le clic sur la carte ouvre toujours Batterie.

Validation native : en-tête complet et indice « Excellent » autour de 86–87 %
observés avec ses contributions, détail ouvert puis fermé par Échap, source sur
batterie, capacité estimée, autonomie, protection active, jauge Mac et puissances
par processus en watts observées. Toutes les cartes et actions tiennent sans
zone de défilement dans la disposition normale. Aucun accessoire supplémentaire
ni chargeur secteur n’était disponible dans cette observation ; ces chemins ont
été vérifiés par fixtures. Les paliers critiques ont été simulés en tests,
sans provoquer de pression mémoire ou d’état thermique critique sur le Mac.
La qualité d’un diagnostic matériel, VoiceOver complet, clavier seul, grands
textes et autres tailles physiques de moniteur ne sont pas validés par ce contrôle.


## GPU, ventilateurs et raccourcis — vérification du 6 novembre 2026

`TrayHardwareMetrics` lit IOAccelerator pour la charge du GPU, son identifiant,
son modèle et ses cœurs. Le GPU le plus actif est retenu lorsque plusieurs
accélérateurs répondent ; l’historique est réinitialisé si son identifiant change.
`CMacCareSMC` filtre les capteurs HID `GPU MTR Temp` pour la température GPU,
distincte des capteurs CPU. Les températures et ventilateurs sont relus au plus
toutes les cinq secondes dans le sampler, hors du thread de l’interface ; la
charge GPU suit la cadence normale d’une seconde. Les courbes restent brutes.

La lecture SMC des ventilateurs est limitée à `FNum`, `F{n}Ac` et `F{n}Mx`,
avec au maximum huit ventilateurs. Les formats fpe2, ui16 et float sont contrôlés
(taille, finitude, plage 0–30 000 tr/min). Une absence de lecture reste
indisponible, distincte d’une vitesse mesurée nulle ou d’un nombre de ventilateurs
nul. Les ajouts ne sollicitent aucune commande de vitesse ou de mode.
La température GPU est indisponible si les capteurs HID correspondants n’existent
pas ; pas de substitution par la température CPU. Compatibilité Intel et GPU
externes non validée matériellement.

Build Release, signature profonde stricte, plist et `git diff --check` réussis.
53 tests ciblés passent, dont six nouveaux tests GPU/ventilateurs/raccourcis,
plus neuf assertions C sur le décodage des vitesses. Les logs se trouvent dans
`build/tray-layout-qa/`. Observation native du paquet exact : GPU Apple M1, huit
cœurs, charge variable 0–12 %, environ 30 °C, un ventilateur à 0 tr/min,
maximum lu de 7 199 tr/min. Les six cartes et la batterie tiennent sans zone
de défilement. Réglages blancs, choix Aucun puis restauration de Maintenance,
masquage effectif du quatrième raccourci, ouverture de Maintenance sans exécution
et retour à l’accueil via l’icône MacCare vérifiés. Le bloc batterie conserve
son implémentation ; chargeur 65 W et deux accessoires AirPods étaient cette
fois présents dans la lecture native. Aucun essai de mise en rotation forcée.

Les noms accessibles et aides sont présents dans l’arbre natif. VoiceOver complet,
clavier seul, grands textes et autres moniteurs ne sont pas déclarés validés.
État de la QA avant publication : développement non livré sur `main` à `134b7bc` avec modifications de travail,
aucune installation utilisateur. SHA-256 du binaire `/Applications/MacCare.app`
conservé : `78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.


## Publication et clôture — 6 novembre 2026

La [PR #17](https://github.com/M0okz/maccare/pull/17) est fusionnée et la branche
`codex/compact-menu-bar` supprimée en local et à distance. CI de branche, PR et
`main` réussies. Le [workflow Release macOS](https://github.com/M0okz/maccare/actions/runs/42230295376)
a publié la version 0.2.10 (12), le 6 novembre à 15 h 10 (Paris).

Contrôles locaux complets : 94 tests Rust réussis, deux ignorés ; 246 XCTest et
226 Swift Testing réussis ; 15 tests Python de release, frontière PowerUI sans
appel natif d’écriture et signatures Sparkle réussis. Ces suites ont également
été exécutées par les chaînes CI applicables. Le DMG public téléchargé a été
vérifié : intégrité, signature, tickets Apple sur l’app réellement embarquée et
sur le DMG, Gatekeeper `Notarized Developer ID`, identifiants/équipe inchangés,
arm64 pour app et helper, build 12 supérieur au build 10 installé, signatures
Ed25519 du flux et du DMG, flux latest identique à la release.

SHA-256 DMG : `e3001f4ff023cd23eb3ef8d7d3d40870628f0568289eb919afe518a154106a95`
(10 204 866 octets). Preuves sous `build/release-0.2.10-validation/`.
L’installation quotidienne est conservée en 0.2.8 (10) ; son SHA-256 ne change pas.
Aucune mise à jour Sparkle réelle vers 0.2.10 n’a été effectuée dans cette tâche.
Les limites de QA matérielle et d’accessibilité ci-dessus restent applicables.

## Détails Stockage et Batterie — correction Dev du 6 novembre 2026

Correction locale **non publiée** après 0.2.10. Les cartes Stockage interne et
Batterie ouvraient directement leur module dans la fenêtre principale, alors que
CPU, mémoire et réseau disposaient d’un popover. Elles ouvrent maintenant un
popover ancré au volet, avec la même surface violette et une sélection unique
`TrayDetailSelection`. Un bouton explicite permet ensuite d’ouvrir l’outil complet.

`TrayStorageDetail` présente l’espace disponible, utilisé, total et l’occupation
estimée avec un anneau. Les valeurs proviennent du même relevé `DiskSpace` que la
carte (actualisé toutes les dix secondes), sans parcours des fichiers. Le disponible
macOS peut inclure de l’espace purgeable ; ce point est expliqué dans le détail.
`TrayStorageUsage` rejette une capacité nulle et borne le disponible à la capacité
pour éviter un dépassement arithmétique ou une jauge invalide.

`TrayBatteryDetail` observe le `BatteryModel` existant et reçoit la télémétrie du
volet : charge, alimentation/autonomie, capacité restante estimée, cycles,
température, état, chargeur annoncé, protection, processus énergivore ou repli CPU
et accessoires. Une erreur de contrôle reste indiquée comme état indisponible.
Aucune nouvelle commande matérielle ni nouvelle boucle de lecture n’est créée.
`TrayDetailSurface`, `TrayDetailRow` et `TrayActionStyle` partagent le cadre et les
contrôles ; les fenêtres d’activité existantes gardent leurs types de métrique.

Référence de travail : branche `codex/tray-storage-battery-details`, base `ec8cca3`.
Paquet Dev : `build/tray-details/MacCare.app`, installé sur demande dans
`/Applications/MacCare Dev.app` (0.2.10, build 12, signature Apple Development).
La release publique 0.2.10 ne contient pas encore cette correction ; la copie
quotidienne `/Applications/MacCare.app` reste en 0.2.8 (10), inchangée.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).


## Santé du disque dans Stockage interne — Dev du 7 novembre 2026

Le sous-volet Stockage interne lit désormais les indicateurs matériels par le
smartctl embarqué, en plus de l’occupation du volume. Statut, température et
endurance consommée apparaissent avant le détail des capacités. L’action Voir
la santé des disques ouvre Outils → Santé des disques ; l’exploration des fichiers
conserve son action distincte. Lecture seulement à l’ouverture du sous-volet,
sans mesure périodique de fond ni installation Homebrew. La hauteur du détail
est 640 points, avec défilement. Évolution non livrée ; voir
[les outils natifs](native-file-disk-tools.md).

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.

## Icônes des processus auxiliaires — Dev du 8 novembre 2026

Dans les listes CPU et mémoire partagées avec les fenêtres d’activité,
`TrayProcessIconResolver` reprend l’icône de l’application englobante pour les
helpers, en conservant leur nom et leur PID. Les services système sans paquet
application gardent le symbole générique. La mise en cache et les contrôles
préalables aux fermetures restent inchangés. Correctif Dev non publié après
0.2.14 ; [résolution, contrôles et limites](process-icons.md).
