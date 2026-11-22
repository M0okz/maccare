# Stabilisation et empreinte système — 15 novembre 2026

## Livraison 0.2.28 — 15 novembre 2026

**Publié et installé.** [MacCare 0.2.28 (build 30)](https://github.com/M0okz/maccare/releases/tag/v0.2.28) livre les
correctifs ci-dessous, ainsi que l'isolation du minuteur de diagnostic disque
validée après l'échec initial de CI. `/Applications/MacCare.app` est mise à jour
depuis 0.2.26. [Preuves de livraison et limites](release-integration-0.2.28.md).
Les états « non livré » et 0.2.26 conservés plus bas décrivent la campagne Dev
antérieure à cette publication.

## Mesure de la copie installée 0.2.28 — 15 novembre 2026

**Vérification en usage réel, sans modification du logiciel.** Le processus observé
est celui de `/Applications/MacCare.app`, version **0.2.28 (30)**, signé Developer
ID et notarialisé. Son chemin et celui du helper sont résolus depuis leurs PID ;
l'ancienne prévisualisation Dev encore présente dans la session est exclue.
La machine reste le MacBookPro17,1, M1, 8 Go, macOS 27.0.1. L'application était
déjà ouverte depuis plus de vingt minutes ; aucun redémarrage n'est utilisé pour
réduire artificiellement son empreinte. Les autres applications restent actives,
sans compilation ni suite de tests pendant les intervalles.

| Scénario installé | Durée | CPU moyen (% d'un cœur) | Pic CPU échantillonné | Empreinte physique moyenne / pic (Mio) |
| --- | ---: | ---: | ---: | ---: |
| Repos, fenêtre fermée, avant navigation | 90 s | 0,129 | 4,7 % | 56,69 / 56,77 |
| Accueil visible | 60 s | 2,726 | 16,7 % | 65,65 / 66,16 |
| Analyse Nettoyage Recommandé, répétition 1 | 6,069 s | 55,84 | 323,5 % | 66,61 / 66,75 |
| Analyse Nettoyage Recommandé, répétition 2 | 5,906 s | 59,02 | 266,4 % | 66,69 / 67,06 |
| Repos, fenêtre fermée, résultats conservés | 90 s | 0,162 | 14,0 % | 67,64 / 67,69 |

**100 % CPU correspond à un cœur logique**, sur les huit disponibles ; les pics
d'analyse utilisent brièvement plusieurs cœurs. Le temps CPU consommé par les
deux analyses est de 3,389 et 3,486 secondes. Les trois analyses lancées se
terminent avec un bilan de 22,72 Go à examiner, sans suppression. La première
préchauffe les caches : son horodatage de départ n'a pas été conservé après
troncature de la sortie d'observation ; ses échantillons bruts restent présents,
mais elle est exclue des moyennes d'analyse bornées. Les deux répétitions sont
donc des mesures à chaud, pas un benchmark de première analyse après démarrage.
L'accès complet au disque reste absent : les chemins protégés ne sont pas tous
couverts. La durée inclut le déclenchement par l'interface jusqu'à la date de
fin enregistrée par `SmartScanModel`, sans prétendre mesurer sa latence d'affichage.

Le retour au repos est confirmé sur 90 secondes. L'empreinte y varie de 67,52 à
67,69 Mio, avec 67,61 Mio au début et 67,66 Mio à la fin. Elle reste environ 11 Mio
au-dessus du repos initial après affichage du tableau de bord et conservation des
résultats. Cette courte observation ne démontre ni une fuite ni son absence sur
une longue session. Aucun gain global de mémoire n'est établi.

Le **helper privilégié est mesuré séparément** : 0,256 % CPU moyen et 14,57 Mio
de RSS moyen après les analyses (pic 14,63 Mio), soit environ **0,42 % CPU pour
app et helper ensemble** dans cet intervalle. À l'accueil : 0,250 % CPU et
14,46 Mio de RSS moyen pour le helper. Son empreinte physique native n'est pas
accessible sans privilèges (`EPERM`, puis `sudo -n` exige un mot de passe) ;
le relevé utilise donc `ps`, sans élévation. RSS et empreinte physique ne sont pas
additionnés comme s'il s'agissait de la même métrique. Le premier repos n'est pas
entièrement couvert par la collecte helper. Les démons macOS et éventuels outils
éphémères ne sont pas intégrés à ces totaux.

**Comparaison avec la campagne Dev précédente :** les 0,129–0,162 % au repos
installé sont cohérents avec les 0,149 % optimisés et inférieurs aux 0,447 %
observés avant correction. L'accueil installé à 2,726 % reste proche des 2,723 %
avant et 2,773 % après. Cela confirme le faible coût CPU au repos en usage réel,
sans transformer cette comparaison de sessions et signatures différentes en
pourcentage garanti. Il n'existe pas de mesure d'analyse avant correction
comparable : aucun gain de vitesse ou de CPU pendant l'analyse n'est revendiqué.
L'énergie, l'autonomie et la fluidité en images par seconde ne sont pas mesurées.

Méthode : `proc_pid_rusage(RUSAGE_INFO_V4)` toutes les 250 ms, conversion du temps
CPU par la base Mach, empreinte physique incluant la compression et contrôle de
l'identité de démarrage du PID. Les compteurs cumulatifs sont interpolés aux
bornes des phases ; les pics sont des pics échantillonnés et peuvent manquer des
pointes plus courtes. Le helper est relevé par `ps` toutes les secondes (temps CPU
à 0,01 s près). Preuves locales conservées sous
`build/footprint-installed-0.2.28/` : `samples.jsonl`, `helper-ps.jsonl`,
`phases.json`, `summary.json` et identification des processus. Les collecteurs
temporaires sont arrêtés et supprimés. L'application reste ouverte sur À propos
en 0.2.28 ; aucun réglage, autorisation ou fichier utilisateur n'est modifié,
hormis les résultats et dates d'analyse normalement enregistrés par l'app.

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

## Accueil et nettoyage en DEV le 22 novembre 2026

Dans le tableau Processus, la recherche par nom ou PID filtre le dernier relevé
déjà trié. Un nouveau relevé ou un changement de colonne actualise le tri.
Smart Scan calcule la taille de chaque groupe à sa création, publie une seule
sélection quand on décoche le groupe et évite de republier une progression
identique. Dans le nettoyage ciblé, changer de catégorie ou relancer un scan
annule le relevé précédent. Seul le scan actif peut publier son résultat ou son
erreur. Le tri des fichiers se fait sur le thread de travail.

État local sur `codex/stability-footprint`, base `a30874e`. Paquet de validation
`build/home-preview/MacCare.app`, UUID arm64
`9600A0D6-191B-3371-A5EF-5D261161AA5C`, signature Apple Development vérifiée.

| Mesure du processus MacCare Dev | Avant | Après |
| --- | ---: | ---: |
| CPU moyen à l’accueil, fenêtre visible sur 32 s, en % d’un cœur | 3,46 % | 2,32 % |
| Pic d’empreinte physique pendant cette fenêtre | 86,88 Mio | 63,45 Mio |
| Analyse depuis le bouton jusqu’au bilan, médiane de trois essais | 3,08 s | 3,18 s |
| Temps CPU de l’app pendant ces analyses, médiane | 0,67 s | 0,59 s |
| Publications de sélection pour décocher 2 000 éléments, test du modèle | 2 000 | 1 |

L’accueil a été mesuré avec `app/Diagnostics/footprint.c`. Les analyses ont
parcouru les fichiers accessibles sur le Mac depuis l’interface, sans suppression.
La durée inclut la détection du bilan par l’accessibilité macOS. Les caches,
l’ancienneté des deux processus et l’activité des autres apps varient. Le second
paquet inclut aussi un ajustement des titres des cartes. Ces fenêtres courtes
ne permettent pas d’attribuer l’écart global de CPU ou de mémoire à la seule
correction, ni de conclure à une accélération du scan.

Dans la fenêtre DEV, la recherche « MacCare » est passée de 401 à deux lignes.
Effacer la recherche a rétabli le tableau complet. Les colonnes PID puis Mémoire
ont répondu au changement de tri. Deux tests de régression reproduisaient
la publication de 2 000 sélections et l’affichage d’un résultat de l’ancienne
catégorie. Ils passent après correction. Suites Swift complètes avec 389 tests
XCTest recensés, dont sept ignorés, et 277 tests Swift Testing réussis.
