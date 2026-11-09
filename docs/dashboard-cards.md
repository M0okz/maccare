# Accueil : bilan, batterie et santé

## Activité stable — Dev du 9 novembre 2026

**En développement, non livré.** Les courbes des cartes CPU, GPU et réseau couvrent dix minutes et continuent à être alimentées hors de l’accueil. L’ouverture des détails donne accès à dix minutes, trente minutes ou une heure, avec moyenne et pic, également pour la RAM. Le GPU est désormais un bouton ouvrant son détail. Les cartes conservent leur taille et leur composition ; les chiffres sont lissés sur cinq secondes et changent toutes les trois secondes. L’échelle réseau utilise des paliers avec baisse différée.

Voir [le fonctionnement, les vérifications et leurs limites](activity-metrics-cache.md).

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

## Cache d’activité — Dev du 8 novembre 2026

Après la publication 0.2.14, les valeurs et courbes d’activité restent en mémoire
au changement d’onglet ou à la fermeture du volet. Le suivi reste lié à la
visibilité, sans nouveau relevé en arrière-plan. Les pauses et l’expiration des
anciens points restent réelles. Voir [le fonctionnement et les limites](activity-metrics-cache.md).


## Simplification Batterie — Dev du 8 novembre 2026

Évolution sur `codex/battery-card-polish`, non publiée. Les anneaux de l’accueil
sont réservés à trois accessoires au maximum, alignés à droite dans une zone de
taille fixe. Le Mac n’y figure plus puisque son niveau est déjà affiché en grand.
La rétention des niveaux pendant 20 secondes reste inchangée. Les descriptions
historiques ci-dessous conservent leur date et leur périmètre de livraison.

Le titre visible « Processus le plus énergivore » est retiré de l’accueil. Une
seule ligne conserve l’icône de l’application (ou une icône neutre), son nom et la
puissance en watts. Le résumé accessible garde le sens de la mesure ; un repli
CPU reste exprimé en pourcentage avec son explication au survol, sans inventer
de watts. La ligne garde une hauteur stable, sans animation de remplacement.

La télémétrie batterie partagée relit les processus toutes les 15 secondes,
tandis que chargeur et accessoires gardent leurs lectures toutes les 5 secondes.
Deux relevés initiaux rapprochés d’une seconde amorcent les compteurs ; une longue
interruption réamorce ces compteurs. La mesure précédente est conservée entre
les relevés. La limite de validité des deltas est portée à 30 secondes uniquement
pour cet échantillonnage ; les listes CPU/mémoire gardent leurs paramètres.
MacCare, MacCare Dev, leurs processus embarqués et le helper sont exclus du
classement énergétique et de son repli CPU. Les listes générales ne sont pas filtrées.

| Before | After | Why |
| --- | --- | --- |
| Anneau du Mac à côté de son grand pourcentage | Anneaux réservés aux accessoires | Supprimer la répétition |
| Titre et ligne d’application séparés | Icône, nom et valeur sur une ligne | Alléger la lecture sans déplacer les cartes |
| Classement renouvelé toutes les 5 secondes | Mesure moyenne à 15 secondes | Réduire les changements visuels et les lectures |
| MacCare peut arriver en tête | MacCare et ses auxiliaires exclus | Mettre en avant les autres applications |

Contrôles : 20 tests ciblés réussis (télémétrie, cadence, exclusion, accessoires
et présentation batterie), build Release arm64 et signatures strictes du paquet
Dev. Paquet `build/battery-card/MacCare.app`, Dev 0.2.13 (build local 4).
Installé dans `/Applications/MacCare Dev.app` et contrôlé à 1436 × 784 points :
anneaux AirPods/boîtier seuls, états avec et sans accessoires, ligne icône/nom/watts
sans titre, bas des cartes alignés, accès Batterie puis retour à l’accueil et
reprise de la mesure. Le résumé accessible conserve les niveaux et la qualification
énergie/CPU. Pas de campagne complète VoiceOver/clavier, de contrôle sur le 14 pouces
physique ni de test sur secteur. La cadence exacte est vérifiée par les tests,
sans instrumentation native des appels système. La copie quotidienne conserve
son empreinte et la sauvegarde temporaire de la Dev est supprimée. Preuves :
`build/battery-card-qa/`. La distribution 0.2.13 (15) reste inchangée.

## Badge Santé de la batterie — Dev du 8 novembre 2026

Sur la même branche, le badge de l’accueil remplace « Aucune alerte » par
« Santé : 98 % » avec la valeur réelle de `BatterySnapshot.healthPercent`,
distincte du niveau de charge. Sans mesure ou sans batterie, il affiche
« Santé : — ». Le résumé accessible inclut cette santé et conserve l’état
signalé par macOS. La bulle d’aide explique qu’il s’agit de la capacité de charge
restante par rapport à la capacité de conception. La cadence et les autres
mesures ne changent pas. Le nombre réel de cycles remplace le trait de séparation
(« Cycles : — » si inconnu). Le nom de l’app énergivore est en poids normal ;
la ligne garde une hauteur compacte. Les cycles sont également présents dans le
résumé accessible. Paquet Dev 0.2.13 (build local 5), non publié ;
contrôles du build, de la signature et du rendu natif consignés dans
`build/battery-health-badge-qa/`. Pas de nouveau test métier pour ce changement
de texte alimenté par le modèle existant. Rendu natif à 1436 × 784 : badge
« Santé : 82 % », 595 cycles, niveau de charge 58 % séparé, trait retiré, nom
d’app en poids normal et cartes alignées. Résumé accessible relu. La copie
quotidienne conserve son empreinte et la sauvegarde temporaire Dev est supprimée.
Pas de campagne complète VoiceOver/clavier, de QA physique sur le 14 pouces ni
de scénario natif de batterie absente pour cette passe.

## Historique de livraison

Disponible dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), publiée le 7 novembre 2026. Les états Dev et les validations datées ci-dessous décrivent les paquets précédents et conservent leurs limites de QA.

Intégration du 6 novembre 2026, après validation de la maquette. Branche locale
`codex/dashboard-summary-cards`, après la publication 0.2.11. Ces ajouts ne font
pas partie de la release publique 0.2.11.

## Disposition validée — intégration Dev

La deuxième proposition visuelle a été validée par Gregory. Elle remplace la
composition des premières passes décrites plus bas : bilan sur toute la largeur,
colonne Batterie puis Santé à gauche, et Activité en grille 3 × 2 à droite. La
carte autonome Disque de démarrage est retirée de l’accueil ; une seule tuile
Stockage subsiste dans Activité. Aucune donnée fictive de la maquette n’est reprise.

`DashboardView` compose le bilan seul en tête. `HomeCleaningCard` aligne total,
répartition et action circulaire sur une ligne lorsque le contenu dispose d’au
moins 900 points ; sinon il reprend une disposition verticale. Les états sans
analyse, historique sans détail, analyse active, interruption et nettoyage restent
issus du modèle. Les actions Analyser/Suivre/Arrêter ne changent pas de sens.

À partir de 1040 points disponibles, `HomeStatusCards` réserve 36 % de la largeur
à Batterie et Santé empilées, avec 18 points entre cartes. Activité remplit la
hauteur de cette colonne. Plus bas, Batterie et Santé passent d’abord côte à côte,
puis s’empilent si leurs largeurs minimales ne tiennent plus ; Activité vient
dessous et garde son propre repli à deux colonnes. Batterie reprend sa hauteur
naturelle, sans minimum de 256 points ni espaces qui étirent son centre. Les
anneaux de 34 points gardent leurs trois emplacements fixes et la rétention de
20 secondes. Les noms/niveaux restent accessibles et au survol.

`HomeHealthCard` remplace le doublon par un contexte : état, raison principale,
nom réel du Mac, RAM/macOS et uptime. Pas de capacité ni de jauge de stockage dans
cette carte. Le résumé `HomeHealthPresentation` réutilise `MacHealthScore` et le
seuil existant `StorageAlertPolicy.isLow`, sans changer le barème ni le suivi des
mesures. Il distingue Tout va bien, À surveiller, À vérifier, Lecture en cours et
Mesures partielles. Une condition critique prime sur un avertissement ordinaire ;
une mesure manquante ne produit pas un faux état sain. Le clic ouvre le détail
natif des critères existant, avec le grade et le score chiffré réservés à ce détail.
Les mesures CPU instantanées et l’uptime n’influencent toujours pas le calcul.

Après le retour de Gregory sur la hauteur excessive des tuiles, Batterie et Santé
sont resserrées ensemble : marges internes de 18 points, source et puissance du
chargeur sur une ligne, RAM/macOS/uptime sur une ligne. Le nom du Mac reste au-dessus.
La raison courte Santé conserve une seule ligne stable, avec son texte complet au
survol et dans le détail. La grille Activité suit cette colonne plus courte au
lieu d’étirer des tuiles à travers un grand vide. Le style partagé laisse Batterie
et Santé à leur hauteur naturelle ; seul Activité demande explicitement de remplir
la hauteur disponible, ce qui évite de répartir artificiellement la colonne en
deux cartes égales et de comprimer le pied de Batterie.

Polissage selon le skill Emil : mêmes espacements, blancs lumineux et surfaces
violettes ; chiffre principal avec chiffres tabulaires ; hauteur stable pour la
raison courte de santé et le processus ; anneaux sans animation de déplacement ;
focus arrondi suivant le contour des tuiles. Les éléments décoratifs sont masqués à
l’accessibilité et les actions restent des boutons natifs. Les retours de pression
et graphiques existants conservent leur prise en compte de Réduire les animations.

Validation de cette passe : 33 tests ciblés réussis (résumé de santé, barème,
accessoires, persistance et retours du nettoyage). Build et vérification du paquet
Dev dans `build/dashboard-approved-qa/`. Le rendu natif à 1436 × 784 a été contrôlé : disposition 36/64, haut/bas alignés,
Batterie compacte, anneaux, Santé avec mesures réelles, un seul stockage, bilan
horizontal et accès au détail Santé. Après le retour sur les hauteurs, le rendu
final confirme des tuiles moins hautes, la marge sous le processus Batterie et la
hauteur naturelle distincte des deux cartes de gauche. Échap referme le détail Santé. Analyser revient à
la préparation sans déclencher de scan. Le contrôle des formats étroits reste
limité : la tentative par le menu natif a été interrompue par des changements
d’état de l’application ; aucun repli étroit n’est déclaré visuellement validé.
Pas de campagne complète VoiceOver/clavier/grandes tailles/Réduire les animations. Paquet local
`build/dashboard-approved/MacCare.app`, Dev 0.2.11 (build local 1), non publié.
La copie quotidienne dans Applications est préservée.


## Bilan du nettoyage

`HomeCleaningCard` remplace le contenu directement dessiné dans `DashboardView`.
Il conserve l’action circulaire, désormais **Analyser**, et ajoute une barre
proportionnelle ainsi qu’une légende avec les tailles par famille. Les catégories
sans données ne sont pas inventées pour reproduire les chiffres de la maquette.
Les règles actuelles produisent notamment Caches et Journaux ; les fichiers
temporaires et les autres règles sûres sont représentés seulement si présents.

`HomeCleaningBreakdown` agrège exclusivement les groupes au risque `safe`, comme
le total `safeSize` de l’accueil. Les autres résultats ne gonflent pas ce total.
Les familles inconnues restent dans Autres, sans disparaître du calcul. Les
légendes passent en liste si elles ne tiennent pas sur une ligne ; la barre
décorative est masquée à l’accessibilité, les montants restant lisibles séparément.

Le clic **Analyser** revient à la préparation du nettoyage, sans lancer le moteur
ni conserver un ancien panneau d’outils ouvert. Pendant un scan ou une suppression,
**Suivre** ouvre l’opération en cours et ne la remet pas à zéro. Le lien redondant
Relancer l’analyse est retiré de cette carte.

`SmartScanModel` mémorise la répartition complète sous la nouvelle clé
`lastSmartScanSafeBreakdown` : date du scan et dictionnaire des tailles par famille.
Les clés historiques restent inchangées. Au chargement, date et somme doivent
correspondre au dernier bilan mémorisé ; valeurs booléennes, négatives,
fractionnaires, inconnues et sommes débordantes sont refusées. Une ancienne copie
peut modifier le total/date sans connaître cette clé : son nouveau bilan ne sera
pas associé à une ancienne répartition. Un bilan historique sans répartition
affiche un message jusqu’à la prochaine analyse, sans valeurs fictives.

## Batterie

`HomeBatteryCard` garde son accès au module Batterie et son état d’alimentation.
La capacité et les cycles quittent la carte d’accueil ; ils restent accessibles
dans le module complet. Après simplification demandée par Gregory, la jauge
horizontale et la section nommée Appareils connectés sont remplacées par les seuls
pictogrammes dans des anneaux de 40 points : ce Mac, puis jusqu’à deux accessoires.
Les noms et niveaux restent au survol et dans le résumé accessible, sans légendes
ni pourcentages sous les anneaux. Les trois emplacements gardent une largeur et
une hauteur constantes, même lorsqu’aucun accessoire n’est disponible. La rangée
passe sous le niveau principal si la largeur ne suffit pas.

`TrayBatteryAccessoryHistory`, utilisé par le contrôleur partagé, stabilise les
relevés : une absence ponctuelle conserve le dernier niveau connu pendant au
maximum 20 secondes depuis sa dernière lecture. L’expiration est individuelle,
et un nouveau niveau reçu remplace immédiatement le précédent. L’ordre et les
identifiants de présentation restent stables lorsque les listes sont partielles
ou que macOS change son numéro de source. Deux appareils portant le même nom
restent distincts si leurs sources les distinguent. Aucun appareil n’est inventé
sur un premier relevé vide. Une longue interruption du suivi fait expirer les
anciens niveaux à la reprise. Les autres mesures du contrôleur restent fraîches.

La puissance annoncée du chargeur est affichée en **watts**, selon le choix de
Gregory, uniquement sur secteur et lorsqu’elle est disponible. Il ne s’agit pas
de la consommation instantanée du Mac. Le processus le plus énergivore accessible
est affiché avec sa puissance et l’icône de son app lorsqu’elle est identifiable.
Si la puissance manque, le repli sur la charge CPU est nommé explicitement.
Absence de batterie, de périphérique ou de mesure distincte de zéro.

La carte réutilise `TrayBatteryController` et `TrayBatteryTelemetry`, dans une
tâche SwiftUI liée à la visibilité réelle de sa fenêtre et à la présence d’une
batterie. La tâche est annulée quand la vue disparaît ou devient masquée ; les
lectures ne lancent ni recherche/appairage Bluetooth ni commande de charge.
Le bloc reste un bouton natif avec libellé, résumé et trait de bouton explicites.

## Proportions de la grille

Les cartes d’une même ligne partagent leurs bords haut et bas. `HomeStatusCards`
dimensionne la ligne selon le contenu ; `HomeStatusCardStyle` permet aux deux
surfaces de remplir cette hauteur. Activité du Mac est enrichi par six tuiles,
inspirées de la référence fournie : Processeur, GPU, Mémoire, Stockage, Réseau et
Ventilateurs. Chaque tuile présente une valeur principale, un état ou une
caractéristique en tête, puis une courbe ou une jauge et un détail de contexte.

La grille affiche trois colonnes lorsque son contenu dispose d’au moins 540 points,
puis deux colonnes. L’ordre de lecture reste CPU/GPU/Mémoire/Stockage/Réseau/
Ventilateurs. Les cartes Batterie et Activité s’empilent lorsque la zone disponible
est inférieure à 800 points. Les accès CPU, mémoire et réseau restent les fenêtres
de détail existantes ; Stockage ouvre Espace disque. GPU et Ventilateurs restent
en lecture seule, sans bouton trompeur ni commandes de vitesse.

Les mesures CPU/GPU/mémoire/réseau/ventilateurs viennent du même `TrayMetricsStore`,
sans nouvel échantillonnage. Le stockage réutilise le relevé `DiskSpace` déjà fait
par l’accueil, comme la carte de la première ligne. La pression mémoire est le
niveau réellement exposé par macOS, distinct du pourcentage d’utilisation estimé.
Le pourcentage des ventilateurs est le rapport vitesse/vitesse maximale, pas une
commande. Le réseau affiche type, IP locale et débits descendants/montants en Mb/s.

Les composants reprennent le violet, les blancs lumineux et la surface batterie
légèrement verte. Coins 22 points, contenu à 22–24 points, bouton circulaire 90
points, chiffres principaux adaptatifs de 40/36 points, anneaux d’accessoires de
40 points. Pas d’animation de déplacement ajoutée ; le retour de survol existant
respecte Réduire les animations.

## Validation et état de livraison

41 tests ciblés réussis (28 pour les bilans/batterie, 13 pour les mesures et
le suivi partagé) : périmètre sûr, réconciliation de la somme, reprise après
redémarrage, ancien bilan sans détail, persistance corrompue, mise à jour par une
ancienne copie, navigation/profils et relevés batterie. Build Release arm64 et
packaging Dev, signatures profondes et correspondance du binaire compilé avec le
paquet vérifiés. Analyse seule, retour à Analyser, bilan réel, puissance du chargeur,
processus et accès au module Batterie contrôlés dans l’application.

La répartition a été contrôlée après fermeture puis relancement de la Dev. Les
six tuiles, leurs états réels, les anneaux AirPods/boîtier (100 %/64 % au relevé),
l’état sans accessoire et l’alignement haut/bas ont été observés dans l’application
native à 1553 × 784 points. Les appareils peuvent disparaître des données exposées
par macOS entre deux relevés ; l’état vide est alors présenté sans valeurs inventées.
Le redimensionnement n’a pas abouti avec l’automatisation native : le repli à deux
colonnes et l’empilement ne sont pas déclarés vérifiés visuellement à cette passe.
Pas de campagne complète VoiceOver,
clavier, tailles de texte ou Réduire les animations. Aucune suppression ni commande
de batterie ou de ventilateur n’a été exécutée. Le contrôleur de charge signale
toujours son indisponibilité préexistante dans le module complet ; aucun dépannage
matériel ajouté à cette évolution de l’accueil.

Paquet `build/dashboard-cards/MacCare.app`, installé dans
`/Applications/MacCare Dev.app` (Dev 0.2.11, build local 1), lancé avec
`-battery.protection.resume NO`. La copie quotidienne reste préservée. Preuves
locales : `build/dashboard-cards-qa/`. Travail non publié.

## Stabilisation des accessoires — 6 novembre 2026

Cause reproduite : le contrôleur remplaçait les accessoires à chaque relevé, y
compris un relevé vide temporaire ; la section passait alors d’anneaux légendés à
un message plus court. Un relevé natif IOPS de 20 secondes a montré huit lectures
vides, puis les mêmes deux appareils. Le changement de hauteur est aussi supprimé
par la rangée d’icônes à dimensions constantes. La ligne de processus garde une
hauteur minimale constante lorsque son icône d’application apparaît ou disparaît.

Un test a d’abord échoué sur la disparition au premier relevé vide. Les 17 tests
ciblés passent ensuite : rétention, expiration individuelle, mise à jour des
niveaux, ordre, changement de source, noms identiques, premier relevé vide,
remise à zéro de l’horloge et télémétrie batterie. Build et contrôle natif après
installation Dev consignés dans `build/accessory-stability-qa/`. Les anneaux
compacts et leurs positions identiques après plusieurs mises à jour ont été
observés à 1553 × 784, avec les niveaux AirPods/boîtier dans le résumé accessible.
Les bords des deux cartes restent alignés. Pas de déconnexion physique forcée,
ni de campagne complète de survol, clavier ou VoiceOver dans cette passe.

Correction documentaire : le numéro du paquet Dev assemblé par défaut est 1,
constaté dans son Info.plist ; le numéro 13 précédemment indiqué dans cette page
correspondait à la distribution publique et ne décrivait pas ce paquet local.
La copie quotidienne reste en 0.2.8 (10). Le correctif reste non publié.

## Alignement du texte Santé — Dev

Après validation de l’aperçu, `HomeHealthCard` utilise une grille à deux colonnes :
une marge d’icônes de 18 points adaptatifs, un espacement de 10 points et une
colonne commune à tous les textes. Titre, statut, raison, nom du Mac et ligne
RAM/macOS/uptime démarrent sur la même verticale. Les lignes gardent les mêmes
polices et espacements verticaux compacts ; le calcul, les relevés et l’accès au
détail ne changent pas. Les icônes et la cellule vide décorative sont masquées à
l’accessibilité ; le résumé du bouton conserve les textes utiles.

Paquet `build/health-alignment/MacCare.app`, identité Dev 0.2.11 (build local 1),
installé uniquement dans `/Applications/MacCare Dev.app`, non publié. Vérifications
et limites de cette passe consignées dans `build/health-alignment-qa/`. Pas de
nouveau test métier pour ce seul changement d’alignement ; les résultats de la
passe précédente restent propres à cette passe.

Contrôle de l’alignement : build Release arm64 et signatures profondes strictes
réussis, UUID compilé/paquet/installé concordants. Rendu natif à 1436 × 784 : colonne
de texte commune, marge d’icônes et hauteur compacte conservées. Le résumé natif
du bouton contient encore le statut, la raison, le nom et les caractéristiques.
Pas de campagne complète VoiceOver, clavier ou grandes tailles dans cette passe.
La copie temporaire de retour arrière est retirée après validation.

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.
