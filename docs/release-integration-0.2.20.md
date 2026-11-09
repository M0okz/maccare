# Livraison MacCare 0.2.20

9 novembre 2026 — [release publiée](https://github.com/M0okz/maccare/releases/tag/v0.2.20), build **22**.
Tag `v0.2.20` sur `708e28b5e5d707aa17495ddadbe500f8e0e8b8bc`, après fusion
de la [PR #28](https://github.com/M0okz/maccare/pull/28).
[Workflow officiel](https://github.com/M0okz/maccare/actions/runs/42662875616) réussi.

## Changements inclus

Le bilan Applications de la PR #27 comprend les apps peu utilisées depuis
30 jours, les incompatibilités identifiables, les installateurs DMG/PKG à
examiner, les aides « i » et l’aperçu mini Dock des mises à jour. Les différentes
sources sont vérifiées en parallèle, avec résultats progressifs, erreurs isolées
et déduplication indépendante de l’ordre des réponses.

Le rappel global de mise à jour, repris du commit `a949a9e` de la discussion
Batterie, affiche un bouton jaune dans les rubriques de la fenêtre principale.
Il ouvre le panneau Sparkle et son changelog, en conservant les choix de report
et de recherche automatique. La refonte Batterie, la réparation de l’assistant
et les priorités d’accessoires livrées en 0.2.19 restent incluses.

## Contrôles

344 XCTest locaux exécutés (un test réseau facultatif ignoré, aucun échec),
259 Swift Testing et 19 tests Python réussis. CI de branche et de PR vertes
sur les mêmes sources ; les tests sont à nouveau exécutés par la chaîne
officielle avant accès aux clés de signature.

Le DMG public téléchargé est vérifié : signature Developer ID, tickets Apple
app/DMG, Gatekeeper « Notarized Developer ID », cinq exécutables arm64,
version et canal de l’assistant cohérents. Signatures Ed25519 du flux et du DMG
validées avec la clé publique de la copie installée ; le flux latest est
identique à celui de cette release.

DMG : **16298670 octets** ; SHA-256
`3212ff7f96ce2ec4df3174cf12e4a08bbfacf90a4ffad0670bf3eaf3b364bdec`.

Dix pages publiques sont actualisées et relues en HTTPS, identiques aux sources.
Le conteneur maccare-site est sain ; seul le HTML a été remplacé, avec droits
conservés. Les anciennes pages ont été vérifiées identiques à leur version Git,
qui fournit le retour arrière. Les fichiers de remplacement temporaires ont été
supprimés. Huit pages Outline sont publiées et relues avec texte antérieur et
emplacement conservés. Le suivi de livraison est [#103](https://todo.homeblack.fr/tasks/7153).

## Limites et copies installées

Aucune installation ni lancement de l’app distribuée. Les empreintes des copies
installées sont préservées. Les aperçus natifs Applications et du rappel ont
été vérifiés dans leurs paquets Dev antérieurs. Le rappel a ouvert le vrai
changelog signé dans un aperçu isolé ; aucune campagne native complète sur
toutes les rubriques, anciens macOS ou VoiceOver n’est revendiquée.
Pas de nouvelle campagne matérielle de charge ; les limites datées de la
refonte Batterie demeurent applicables. Les captures web restent les anciennes
captures explicitement signalées.

Preuves locales : `build/release-0.2.20-qa/`, avec métadonnées GitHub,
`public-validation.json`, `site-validation.json`, `outline-validation.json`
et suivi. Les téléchargements et scripts de travail sont nettoyés après contrôle.
