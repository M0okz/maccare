# Accueil : bilan et batterie enrichis

Intégration du 6 novembre 2026, après validation de la maquette. Branche locale
`codex/dashboard-summary-cards`, après la publication 0.2.11. Ces ajouts ne font
pas partie de la release publique 0.2.11.

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
