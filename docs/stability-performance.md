# Stabilisation et empreinte système — 15 novembre 2026

## Livraison 0.2.28 — 15 novembre 2026

**Publié et installé.** [MacCare 0.2.28 (build 30)](https://github.com/M0okz/maccare/releases/tag/v0.2.28) livre les
correctifs ci-dessous, ainsi que l'isolation du minuteur de diagnostic disque
validée après l'échec initial de CI. `/Applications/MacCare.app` est mise à jour
depuis 0.2.26. [Preuves de livraison et limites](release-integration-0.2.28.md).
Les états « non livré » et 0.2.26 conservés plus bas décrivent la campagne Dev
antérieure à cette publication.

## Périmètre et état

Campagne demandée : vérifier les parcours courants, corriger les régressions
confirmées et diminuer la charge sans retirer de fonction ni ralentir les mesures
visibles. Travail **en développement, non livré**, branche
`codex/stability-footprint`, base `83099d7`. Suivi :
[#130 dans Vikunja](https://todo.homeblack.fr/tasks/7182).

Les sources et le paquet Dev restent dans le dépôt produit. La copie quotidienne
`/Applications/MacCare.app` n'est ni remplacée ni re-signée. Les modifications de
réorganisation déjà présentes dans README, .gitignore et project-layout restent
hors de cette campagne.

## Corrections et contrats préservés

`BatteryHistoryStore` valide la révision du fichier avant de réutiliser son cache
(volume, inode, taille et horodatages de modification/changement à la nanoseconde).
Un relevé inchangé ne décode plus systématiquement tout le JSON. Le verrou
interprocessus reste acquis avant l'ajout : les écritures d'une autre instance
sont relues et fusionnées. La fenêtre de 30 jours est réappliquée à la lecture,
y compris après un recul de l'horloge. La limite de 10 000 points exposés, le
plafond de fichier de 2,5 Mo, les droits privés, les écritures atomiques et la
cadence d'historisation sont conservés. Aucun protocole helper ou réglage de charge
n'est modifié. Le cache décodé reste borné par la taille maximale du fichier.

`SystemTools.run` vide stdout et stderr simultanément. Avant correction, un enfant
remplissant les 64 Kio de stderr se bloquait tandis que le parent attendait stdout.
Le test reproduit le blocage avec 256 Kio de diagnostics et une alarme propre au
processus de test. Les deux sorties et le code de retour restent séparés ; stdin
est fermé pour ces commandes non interactives. Ce correctif ne constitue pas un
délai maximal général pour une commande ou ses descendants.

## Vérification reproductible

Les tests portent sur les interfaces existantes des modèles, du moteur et du
stockage ; les actions de suppression/installations utilisent des données de test.
La QA native couvre navigation, accueil, détails d'activité, fermeture et
réouverture, analyses et annulations, Batterie, Applications, fichiers et outils.
La protection de charge, les autorisations système et les données personnelles ne
sont pas modifiées pour simuler une validation matérielle.

```sh
swift test --package-path app --scratch-path build/swift-tests --build-system native --arch arm64 -Xlinker -L"$PWD/core/target/release"
cargo test --locked --manifest-path core/Cargo.toml
python3 -m unittest discover -s app/release/tests -v
xcrun clang -O2 -Wall -Wextra -Werror app/Diagnostics/footprint.c -o build/footprint
build/footprint PID 30
```

`app/Diagnostics/footprint.c` observe un PID externe en lecture seule avec libproc.
Il rapporte temps CPU converti selon la base Mach, empreinte physique (compression
comprise), réveils et E/S disque. Il vérifie l'identité de démarrage à chaque relevé.
Les mesures concernent le processus app ; elles n'additionnent pas ses outils
enfants ni les services macOS. Elles ne mesurent pas des watts ou une autonomie.
Le compteur CPU est recoupé avec `ps` sur un processus de test borné.

Les journaux et observations locales sont sous `build/stability-2026-11-15/`.

## Tests et parcours vérifiés

La suite Swift finale inclut les deux intégrations réseau explicitement activées
avec `MACCARE_UPDATE_NETWORK_QA=1 MACCARE_INSTALL_NETWORK_QA=1` : 378 tests XCTest,
dont 5 ignorés, et 276 tests Swift Testing, soit **649 tests exécutés réussis**.
Le moteur Rust compte **98 tests réussis**, puis le test séparé de frontière de
volume monté réussit également (**99 au total**). Les **19 tests Python** de release
passent. Le test de signatures Sparkle accepte le flux valide et refuse une clé
incohérente ainsi qu'un flux altéré.

Les harness natifs PowerUI, SMC et batteries d'appareils passent. Le scénario sans
outils développeur passe. Le test de cycle de vie des barres d'outils effectue
640 transitions dans quatre lancements, sans exception de toolbar. Les tests
d'installation réseau utilisent des applications signées téléchargées dans des
répertoires de test : remplacement 0.2.19 → 0.2.20, préférences conservées et refus
d'un checksum incorrect. Ils ne remplacent aucune application utilisateur.

| Parcours natif | Observation sur le paquet Dev |
| --- | --- |
| Accueil | Mesures CPU/GPU/RAM/réseau et espace libre présentes ; autorisation manquante explicitement indiquée |
| Détails d'activité | CPU, GPU, RAM et réseau ouverts ; historiques et processus actualisés ; fermeture puis réouverture de la fenêtre principale réussies |
| Nettoyage | Analyse, annulation, reprise puis résultats ; 22,71 Go à examiner sur ce Mac ; aucune suppression |
| Performances | Analyse terminée, 28 éléments de démarrage recensés ; aucune désactivation |
| Batterie | État matériel, historique à 7 et 30 jours, 2 880 points affichés ; aucun réglage de charge modifié |
| Applications | 46 applications, 14 mises à jour proposées ; détails et actions accessibles ; aucune installation réelle |
| Gros fichiers et doublons | Fixture dédiée : deux gros fichiers, un groupe de doublons ; exemplaire conservé protégé ; sélection puis désélection sans suppression |
| Espace disque | Même fixture : quatre éléments, 294,7 Mo ; carte et liste concordantes |
| Santé des disques | Diagnostic lecture seule terminé : 32 °C, 4 % d'endurance consommée, aucune alerte rapportée |
| Réglages et À propos | Fenêtre native et onglets Général/Menu/Fichiers accessibles ; version Dev identifiée, mise à jour distribuée désactivée ; préférence Carte restaurée après l'essai Liste |

Les cinq tests Swift encore ignorés concernent des scénarios fournisseurs ou
privilégiés distincts de cette campagne. Le test Rust de création/suppression d'un
simulateur Xcode reste ignoré. L'accès complet au disque manque au paquet Dev :
les résultats d'analyse ne couvrent donc pas tous les emplacements protégés.
Cette campagne ne valide pas une veille prolongée, un cycle matériel de charge,
les notifications réelles, VoiceOver exhaustivement, Intel ou les autres versions
de macOS. La réactivité observée dans l'interface ne constitue pas une mesure FPS.

## Charge et limites des mesures

Machine : MacBookPro17,1, Apple M1, 8 Go, macOS 27.0.1 (26A434). Paquets Release
locaux signés Apple Development, même version de base ; autres applications de
la session actives. Les builds et tests sont arrêtés pendant la mesure.

Sur le scénario reproductible de 60 relevés inchangés avec un historique de
10 000 points, le temps passe de **1,330 s à 0,115 s**, soit environ **91 % de moins**.
Ce gain concerne le stockage de l'historique, pas le CPU total de MacCare.
Les tests couvrent aussi une écriture par une seconde instance, un remplacement
de même taille à date de modification conservée, la suppression/corruption du
fichier et l'expiration/recul de l'horloge.

Les cadences existantes sont conservées : mesures d'activité à une seconde quand
elles sont visibles et cinq secondes en arrière-plan, capteurs détaillés réservés
au premier plan, processus détaillés à deux secondes, historique batterie à
quinze secondes avec écriture seulement si nécessaire. Réduire ces cadences
aurait changé la fraîcheur des mesures ou des alertes ; aucun tel compromis
n'est introduit.

| Scénario | CPU avant (% d'un cœur) | CPU après | Empreinte fin avant / après (Mio) |
| --- | ---: | ---: | ---: |
| Accueil visible | 2,723 | 2,773 | 45,20 / 48,60 |
| Fenêtre fermée, suivi actif | 0,447 | 0,149 | 44,67 / 48,49 |
| Détails CPU ouverts | 4,370 | 4,213 | 70,97 / 70,89 |

Chaque fenêtre dure 30 secondes, sauf l'accueil optimisé stabilisé mesuré sur
60 secondes. Sa première fenêtre de 30 secondes était plus chargée : 4,146 %,
53,81 Mio au pic puis 48,60 Mio en fin. Elle est conservée dans les résultats,
pas supprimée de l'analyse. Les autres pics optimisés sont 48,64 Mio à l'accueil,
48,61 Mio fenêtre fermée et 70,95 Mio dans le détail CPU.

Fenêtre fermée, les réveils d'interruption passent de 0,565 à 0,498 par seconde ;
aucun réveil de package inactif n'est observé. Les E/S disque comptées passent de
724 992 à 49 152 octets lus, sans écriture dans ces deux fenêtres. Ces compteurs
dépendent du cache système et du moment des tâches périodiques : ils ne prouvent
pas une réduction identique sur une journée complète. Aucun gain global de
mémoire n'est établi. L'accueil et les détails gardent un coût CPU proche ; le
gain démontré par le test ciblé concerne l'historique, avec une baisse observée
de la charge en arrière-plan. Il ne s'agit pas d'une campagne d'endurance ni d'un
benchmark isolé des autres applications.

## État à la fin de la campagne Dev, avant publication

### Complément pendant la préparation de la 0.2.28

Les deux premières CI de publication ont exposé un défaut supplémentaire dans
`DiskHealthReader.run` : la commande de test ignorant SIGTERM revient normalement
après 2,177 / 2,310 secondes malgré un délai demandé de 0,05 seconde. Le test
attend une erreur en moins de 1,5 seconde. Il passe localement en 0,054 seconde,
ce qui confirme la nécessité de vérifier également l'environnement CI.

Le watchdog utilisait la file globale utility, également utilisée par des lectures
bloquantes. Son callback utilise désormais une file série dédiée de même priorité,
sans boucle permanente, changement de signal ou relâchement du test. Le retard
d'ordonnancement est l'hypothèse principale ; les traces initiales ne permettent
pas de le distinguer entièrement d'un retard dans le lancement du processus.
Les deux suites CI complètes du runner défaillant réussissent ensuite ; le test
termine en 0,374 seconde dans la CI de PR, sans modification de son contrat.

Deux revues séparées (conventions/concurrence et conformité au besoin) ne relèvent
aucun défaut bloquant dans les changements. Le paquet Dev vérifié est
`build/stability-2026-11-15/optimized/MacCare.app`, version locale 0.2.27 (8),
sans flux de distribution. Il est arrêté après les essais. Il ne s'agit pas d'une
nouvelle release utilisateur.

La copie `/Applications/MacCare.app` reste en 0.2.26, signature Developer ID
inchangée ; SHA-256 du binaire avant/après :
`ed275b388af2460d71197c01c0d32eb68ccd486d93b2cb18ddeef0b4cad14be4`.
Les fixtures volumineuses, le paquet de comparaison et les copies documentaires
temporaires sont supprimés après validation. Les journaux, mesures JSON et le
paquet optimisé sont conservés comme preuves et livrable de développement.
