# Recommencer un bilan

## Correction Dev du 6 novembre 2026

Depuis un bilan, recommencer doit revenir à l’écran de préparation. Une nouvelle
analyse démarre uniquement après un clic sur **Analyser**. Cette correction suit
le retour à la préparation ajouté dans Nettoyage.

| Page | Comportement vérifié |
| --- | --- |
| Performances | **Recommencer** réaffiche l’introduction et Analyser, sans relire les éléments de démarrage. |
| Applications | **Recommencer** réaffiche l’introduction et Analyser, sans inventaire ni recherche de mises à jour. |
| Mes fichiers | Déjà conforme : **Recommencer** réaffiche le choix du dossier et Analyser, en conservant le dossier choisi. |
| Espace disque | **Changer d’emplacement** revient au départ. Selon le choix explicite de Gregory, **Actualiser la mesure** conserve sa fonction de mesure du dossier courant. |

`PerformanceOverviewView` remet `performanceAnalyzed` à faux et retire le détail
actif. `ApplicationsAnalysisModel.prepareForNewAnalysis()` revient à la phase
introduction ; `ApplicationsOverviewView` retire le détail actif. Les boutons et
leurs actions refusent le retour pendant les opérations en cours. Les inventaires
déjà lus restent disponibles aux outils. Aucun changement dans Mes fichiers ou
Espace disque, ni dans les moteurs d’analyse ou de suppression.

## Vérifications

- Défaut reproduit dans l’application avant correction : Performances relançait
  l’examen ; Applications restait sur le bilan après son actualisation.
- Nouveau paquet Dev installé : analyse réelle de chaque module, puis clic sur
  Recommencer et contrôle de l’introduction avec Analyser, sans relance.
- Mes fichiers : analyse d’un dossier de test possédé par la QA, puis retour au
  choix du même dossier. Espace disque : mesure du même dossier, actualisation
  conservant le dossier courant, puis retour au départ. Dossier de test supprimé
  après les contrôles ; aucune suppression effectuée par les outils de MacCare.
- Build Release arm64, packaging et signature profonde valides ; 37 tests ciblés
  réussis (Applications, Performances, fichiers, espace disque, navigation et
  régression Nettoyage). Contrôles natifs visuels et d’accessibilité de ces seuls
  parcours ; pas de campagne VoiceOver ou clavier complète.

Branche locale `codex/tray-storage-battery-details`, après `308e1e4`. Paquet
`build/overview-restarts/MacCare.app`, installé dans
`/Applications/MacCare Dev.app`, identité Dev 0.2.10 (12), Apple Development,
sans flux de mise à jour. Lancement QA avec `-battery.protection.resume NO`.
Ces corrections restent non publiées. La copie quotidienne
`/Applications/MacCare.app` reste en 0.2.8 (10), avec son exécutable inchangé.

Preuves locales : `build/overview-restarts-qa/` (build, tests, packaging et
validation). Les correctifs précédents Stockage/Batterie et Nettoyage sont inclus.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).
