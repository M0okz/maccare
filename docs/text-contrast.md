# Textes plus lumineux — 6 novembre 2026

État local non publié, branche `codex/tray-storage-battery-details`, après
`c2e36c7`. Le paquet `build/text-contrast/MacCare.app` est installé dans
`/Applications/MacCare Dev.app`, toujours Dev 0.2.10 (12).

Les libellés non sélectionnés de la barre latérale utilisaient le premier plan
à 82 % d’opacité. Cela leur donnait un aspect grisé. Ils utilisent maintenant
le premier plan opaque. Le fond de sélection et le trait d’état sélectionné
restent présents pour distinguer la rubrique active.

La palette sombre partagée de `DesignSystem.swift` devient :

| Rôle | Avant | Après |
| --- | --- | --- |
| Texte principal (`fg`) | `#F0EBFA` | `#FFFFFF` |
| Texte secondaire (`muted`) | `#C4BADB` | `#E0D9EE` |
| Métadonnées (`faint`) | `#AA9BC4` | `#BFB1D6` |

`RootView` applique explicitement le premier plan à son contenu ; les titres et
libellés qui héritaient du blanc atténué de macOS prennent donc le blanc du thème.
`TrayAppearance.secondary` réutilise le texte secondaire partagé dans le volet
violet. Les palettes claires conservent exactement leurs valeurs et les panneaux
blancs gardent leur environnement clair. Aucune modification de police, de taille,
de disposition, d’animation, de couleur de fond ou de logique fonctionnelle.

## Vérifications et limites

Sur le fond déclaré de la barre latérale Applications (`#351B46`), le contraste
WCAG 2 calculé en sRGB passe de **9,08:1 à 15,04:1** pour les libellés non
sélectionnés, après composition de leur ancienne opacité. Pour les icônes non
sélectionnées, il passe de **8,16:1 à 10,98:1**. L’ancien rendu était déjà lisible ;
la demande porte sur la présence visuelle du blanc et la hiérarchie.

Build Release arm64 et packaging réussis ; signatures profondes strictes du
paquet et de l’installation vérifiées. Rendu natif avant/après examiné sur
l’introduction et le bilan Applications ; textes sombres contrôlés dans le
gestionnaire d’applications blanc et les réglages blancs. Le volet réel a été
ouvert par Fenêtre → Afficher le volet MacCare et ses textes vérifiés. Le retour
Recommencer → Analyser reste fonctionnel. Aucun test nouveau pour ces changements
de couleurs ; pas de campagne complète VoiceOver, clavier ou contraste renforcé.

Les ratios indiqués sont calculés sur les couleurs déclarées, pas extraits de
pixels anticrénelés ou une certification de toute l’application. Les combinaisons
théoriques des jetons avec les 32 fonds de palette sont conservées dans
`build/text-contrast-qa/contrast.json` à titre de repérage : elles ne démontrent
pas que chaque jeton est effectivement utilisé sur chaque fond. Par exemple,
le jeton secondaire sur le stop médian turquoise de Mes fichiers donne 3,68:1,
en dessous de 4,5:1 pour du petit texte ; la composition finale et son placement
n’ont pas fait l’objet d’une mesure de contraste dans cette passe. Les fonds
turquoise et leurs effets n’ont pas changé.

Preuves locales : `build/text-contrast-qa/` (build, packaging, contraste,
identification des paquets et validation). Copie quotidienne
`/Applications/MacCare.app` conservée en 0.2.8 (10), exécutable inchangé.
Lancement Dev avec `-battery.protection.resume NO`. Aucune publication.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).
