# Échelle automatique de la fenêtre principale

## Taille minimale de la fenêtre principale

Disponible dans [MacCare 0.2.34, build 36](release-integration-0.2.34.md).

Le 23 novembre 2026, la fenêtre que Gregory venait de redimensionner dans la DEV
mesurait **1 311 × 773 points**, barre de titre comprise. Ce format devient la
taille d’ouverture des nouvelles fenêtres principales et leur minimum sur chaque
axe. La fenêtre peut toujours être agrandie. Cette évolution est disponible dans
MacCare Dev 0.2.33 (build local 22) sur `codex/main-window-minimum`.

`MainWindowLayout` déduit du cadre la hauteur réelle de la barre de titre pour
calculer le minimum du contenu. Avec une barre de 28 points, il est de
1 311 × 745 points. Même à 85 % de densité, le cadre garde ses dimensions.
Quand l’espace utilisable d’un écran est inférieur au minimum, seul l’axe
concerné est plafonné. La scène et `RootView` partagent cette règle. Les
anciennes migrations qui redimensionnaient et recentraient la fenêtre à
l’ouverture ont été retirées.

Dans la DEV native, depuis 1 480 × 900 points, une demande de 800 × 900 donne
1 311 × 900, et une demande de 1 480 × 500 donne 1 480 × 773. Une réduction
sur les deux axes donne 1 311 × 773. Ces mesures ont été reproduites sur
Accueil et Applications, sur l’écran de développement et dans l’aperçu à 85 %.
Une nouvelle fenêtre ouverte au clavier dans l’aperçu mesure aussi 1 311 × 773.
Les cas d’écrans physiquement plus petits sont couverts par les tests de géométrie.
Les relevés natifs sont conservés dans `build/window-floor-dev/`.

## Densité de l’accueil selon la largeur de la fenêtre

Disponible dans [MacCare 0.2.33, build 35](https://github.com/M0okz/maccare/releases/tag/v0.2.33). [Vérifications de publication](release-integration-0.2.33.md).

En DEV le 23 novembre 2026, sur `codex/dashboard-density` à partir de `edc3fc4`.
Dans une fenêtre étroite sur un grand écran, les deux rangées de cartes prenaient
la hauteur de la carte Batterie. Celle-ci réservait 20 points de plus dès que le
contenu de sa colonne passait sous 270 points de largeur.

Le titre et les cartes s’adaptent désormais à la largeur disponible après le rail
de navigation. L’échelle atteint 100 % à 1 200 points de contenu si l’écran le
permet. Elle conserve le plancher de 85 % et respecte la densité de l’écran sans
cumuler deux réductions. La carte Batterie garde la place nécessaire à son
contenu. Le tableau des processus utilise ses coordonnées natives et la police
système du corps de texte en présentation compacte.

Sur le Mac de développement, une fenêtre de 1 149 × 845 points reproduisait les
neuf lignes complètes du signalement. À dimensions identiques, la hauteur d’une
carte est passée de 207 à 167 points et le nombre de lignes complètes de 9 à 12.
La saisie et l’effacement d’une recherche au clavier ont été exercés dans la DEV.
Ces mesures proviennent de la fenêtre native sur le Mac de développement. Le
rendu physique du moniteur 27 pouces 4K reste à confirmer sur l’autre Mac.

## Anciennes limites de redimensionnement livrées en 0.2.31

En développement dans MacCare Dev sur `codex/stability-footprint`, après `a30874e`.
Les dimensions minimales du contenu sont de 1 120 × 700 points à l’échelle standard.
À 85 %, elles passent à 952 × 595 points. Chaque dimension est plafonnée à l’espace
utilisable de l’écran, après déduction de la barre de titre pour la hauteur.
Ces limites réservent de la place aux cartes et au tableau des processus en bas de l’accueil.
Elles s’appliquent à la fenêtre principale dans toutes ses sections.

Sur l’accueil, le tableau des processus utilise les coordonnées natives de la fenêtre.
Les cartes, le titre et le volet latéral sont mesurés à leur échelle d’affichage.
Cette disposition évite une boucle de calcul des contraintes des cellules AppKit à 85 %.
Les autres pages appliquent leur échelle à l’intérieur de chaque destination.

Le 23 novembre 2026, les essais dans la DEV ont exercé séparément la largeur et la
hauteur, puis les deux axes sur Accueil et Applications. Le cadre complet s’arrête
à 1 120 × 728 points à 100 % et à 952 × 623 points dans l’aperçu compact à 85 %.
L’agrandissement à 1 360 × 820 points et le retour à l’accueil ont aussi été vérifiés.
Les six tests de disposition et les cinq tests de navigation passent. Le cas d’un écran
plus petit que le minimum est couvert par les tests de géométrie.

## Historique de la version 0.2.13

L’adaptation initiale de l’échelle a été publiée dans [MacCare 0.2.13 (build 15)](https://github.com/M0okz/maccare/releases/tag/v0.2.13).

Développement du 8 novembre 2026 sur `codex/compact-interface`, après 0.2.12.
Dev **0.2.13 (build local 3)**, non publiée. La demande porte sur une échelle
cohérente entre les Mac, avec conservation du rendu du Mac de développement.
Configuration cible précisée par Gregory : MacBook Pro 14 pouces avec le réglage
Moniteurs « Plus d’espace ». Ses dimensions logiques exactes n’ont pas été relevées
sur l’appareil ; la politique lit directement l’espace visible de l’écran au lancement.

## Adaptation à l’espace utilisable

`MainWindowDisplayObserver` lit `window.screen.visibleFrame` dans la fenêtre
concernée. La politique utilise les points d’espace de travail, indépendamment
du nombre de pixels Retina. Les notifications de changement d’écran, de backing
et de paramètres des écrans actualisent la présentation. Aucun réglage du
moniteur ou du système n’est modifié.

`MainWindowLayout` conserve 100 % lorsque l’espace disponible atteint
2 400 × 1 400 points. En dessous, la densité est calculée par le plus petit
rapport à ces deux références, arrondi vers le bas par pas de 5 %, avec un
plancher de 85 %. Sur l’espace de référence constaté ici, 2 560 × 1 488 points,
l’échelle reste à 100 %. Les cas 1 800 × 1 053 et 1 728 × 1 029 donnent 85 %.
Ces seuils sont une politique de présentation, pas une détection de modèle matériel.

`DisplayAdjustedContent` ajuste d’abord les dimensions proposées au contenu,
puis son rendu. Cela conserve la surface disponible et les replis des vues.
La version 0.2.13 conservait une taille minimale logique de 940 × 620 après conversion.
L’état des modèles reste dans `AppState`, sans nouvelle analyse déclenchée par
le changement de densité. Aucune animation de changement d’échelle n’est ajoutée.
Les réglages, fenêtres de mesures et volet de barre des menus gardent leur
présentation existante ; seul `RootView` est concerné.

## Fenêtres restaurées

Sur un espace compact, le format de départ vise un contenu de 1 360 × 760 points
avant adaptation, soit 1 156 × 646 à 85 %. La grille d’accueil garde ainsi ses
deux colonnes principales. Le format standard de départ reste 1 200 × 720.

Une fenêtre restaurée trop grande est réduite et recentrée une seule fois lors
du premier passage en présentation compacte, via la nouvelle clé locale
`mainWindowCompactDisplayLayoutApplied`. Dans la version 0.2.13, une fenêtre
déjà plus petite conservait sa taille et sa position. Les fenêtres plein écran ou réduites sont exclues.
Les redimensionnements manuels suivants restent mémorisés par macOS.

## Revue selon Emil

| Before | After | Why |
| --- | --- | --- |
| Échelle fixe malgré des espaces de travail différents | Densité adaptée à l’écran de la fenêtre | Réduire l’encombrement sur les espaces plus contraints |
| Grande taille restaurée inchangée | Réduction initiale bornée, sans agrandir une petite fenêtre | Corriger l’encombrement sans effacer les choix suivants |
| Rendu actuel apprécié sur le Mac de développement | Présentation à 100 % conservée ici | Préserver la référence visuelle validée |

## Vérifications et limites

Build Rust/Swift Release arm64 et signatures du paquet réussis. **12 XCTest**
(navigation et fichiers) et **5 Swift Testing** de disposition réussis, avec
cas paramétrés. Les tests couvrent la référence actuelle, des espaces Retina
plus contraints, les informations absentes, la taille restaurée et la conservation
du canevas. Les données des modèles et les routes existantes ne changent pas.

Dans le paquet natif, le rendu courant reste identique à 1 436 × 784. Un aperçu
Dev d’espace 1 800 × 1 000 a vérifié la présentation à 85 % dans cette même
fenêtre : grille, textes, ouverture/fermeture du détail Santé, navigation vers
Nettoyage et réglages blancs. L’accès au détail Santé et sa fermeture par Échap
fonctionnent. La tentative de redimensionnement à la souris n’a pas modifié la
fenêtre ; le format réduit cible est vérifié par les tests de géométrie, sans
preuve visuelle à 1 156 × 646. Pas de test sur l’autre Mac physique, de déplacement
réel entre deux écrans, ni de campagne complète VoiceOver/clavier/grandes tailles.

L’aperçu s’active uniquement dans un paquet Dev avec
`--preview-compact-display`. L’argument de processus
`-mainWindowCompactDisplayLayoutApplied YES` évite d’écrire la migration de
fenêtre pendant cet aperçu. La distribution ignore le drapeau d’aperçu.
La Dev installée est relancée sans ces arguments, avec
`-battery.protection.resume NO`, sur son accueil normal. À propos confirme
0.2.13 (3). La copie quotidienne est préservée.

Preuves : `build/display-layout-qa/`, paquet `build/display-layout/MacCare.app`.

Références Apple : [espace visible de l’écran](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe),
[échelle et dimensions d’une vue](https://developer.apple.com/documentation/swiftui/view/scaleeffect(_:anchor:)).

## Publication 0.2.13 — 8 novembre 2026

Cette adaptation est publiée dans [MacCare 0.2.13 (build 15)](https://github.com/M0okz/maccare/releases/tag/v0.2.13), tag `v0.2.13` sur `9a9dc5612dd9bf6b02c9438c3e721f2ca85efb2b`, après fusion de la [PR #20](https://github.com/M0okz/maccare/pull/20). La branche `codex/compact-interface` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des notes précédentes ; les validations datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42512588574) est réussi, comme les CI de branche, de PR et de fusion. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, notarisation et tickets app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; le flux latest correspond à la release. DMG : 15944980 octets, SHA-256 `0b790855ba2803ada5d33b1cea43c156bdc39dfebcc63719a6a9241c282e2a04`. Le site public propose ce paquet avec les mêmes taille et empreinte ; son HTML correspond aux sources et le conteneur est sain.

Le rendu sur le MacBook Pro 14 pouces en « Plus d’espace » reste à confirmer physiquement ; le format réduit cible a été testé par géométrie, l’aperçu compact étant observé dans une fenêtre plus grande. Pas de validation réelle de déplacement entre écrans ni de campagne complète d’accessibilité. Aucune installation quotidienne effectuée : la copie quotidienne et la Dev 0.2.13 (3) sont préservées. L’application de distribution n’a pas été lancée dans cette livraison. Preuves : `build/release-0.2.13-qa/`.

## Publication 0.2.31 — 23 novembre 2026

La taille minimale et la disposition du tableau des processus décrites dans l’aperçu du 23 novembre sont disponibles dans la version publique 0.2.31 (build 33). Voir les [preuves de livraison](release-integration-0.2.31.md).
