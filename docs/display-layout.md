# Échelle automatique de la fenêtre principale

Disponible dans [MacCare 0.2.13 (build 15)](https://github.com/M0okz/maccare/releases/tag/v0.2.13). Les notes Dev ci-dessous restent un historique daté avec leurs limites de validation.

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
La taille minimale logique existante, 940 × 620, est conservée après conversion.
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
`mainWindowCompactDisplayLayoutApplied`. Une fenêtre déjà plus petite n’est
pas agrandie ni recentrée. Les fenêtres plein écran ou réduites sont exclues.
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
