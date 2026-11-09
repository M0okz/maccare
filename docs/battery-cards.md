# Batterie — vue d’ensemble par blocs

9 novembre 2026. **En développement, non livré**, branche
`codex/battery-cards`, base d’intégration `ddc711d` (préparation 0.2.17).
La maquette a été validée par Gregory avant implémentation. Cette évolution
ne constitue pas une release et ne remplace aucune copie dans Applications.

## Organisation

Le résumé conserve les mesures réelles : charge, alimentation, capacité estimée,
cycles et température. Six blocs reprennent les cartes de Mes outils :
Protection de la batterie, Profils d’utilisation, Décharge contrôlée,
Programmations, Historique et Appareils Apple. Le fond reprend la palette verte
existante de Batterie ; les icônes utilisent le même accent de catégorie,
avec la typographie, les surfaces et les actions communes à MacCare.

Chaque bloc ouvre un panneau clair intégré à la fenêtre. `ManagerPanelStyle`,
`ScreenToolbar`, `ManagerBrowserLayout` et `AdaptiveActionRow` fournissent le
cadre commun : Retour/Échap, navigation de rubrique à gauche, détail défilant
à droite, barre d’actions en bas. Les actions de protection et leur confirmation
existante passent dans cette barre. Les explications de fonctionnement et le
diagnostic restent accessibles sous « Fonctionnement et compatibilité » ;
la feuille de diagnostic conserve `ManagerSheetStyle`.

L’ouverture d’un bloc ne lance aucune commande de charge. Le modèle, les
conditions de compatibilité, de propriété de session, les restaurations et les
confirmations restent ceux de l’implémentation existante. Les appareils Apple
restent accessibles en l’absence de batterie interne ; les autres blocs exigent
une batterie détectée. Les profils, programmations et historiques sont conservés.

## Composants

- `BatteryView.swift` : aperçu, télémétrie compacte et cartes adaptatives.
- `BatteryCategory.swift` : titres, descriptions, symboles et actions des six rubriques.
- `BatteryDetailPanel.swift` : cadre intégré et contrôles de protection existants.
- `BatteryDischargeView.swift` : renvoi vers la nouvelle rubrique Protection.
- `OverviewIntroduction.swift` : surface des sections Batterie adaptée au panneau clair.

Les images décoratives sont masquées aux technologies d’assistance, les cartes
ont un libellé et une indication d’action, la sélection du navigateur est un
trait, le retour rétablit le focus accessible sur la carte et les transitions
respectent Réduire les animations.

## Vérifications

Compilation Release arm64 et signature profonde stricte du paquet Dev réussies.
29 tests XCTest et 35 tests Swift Testing ciblés passent : navigation,
protection, sécurité du modèle, contrôle natif, automatisations et activation
de l’assistant. Aucun nouveau test ne duplique la composition des cartes.

La campagne native vérifie l’aperçu avec les mesures réelles, les six rubriques,
la navigation gauche/droite, le panneau clair, le repli des explications,
la feuille Diagnostic claire et sa fermeture par Échap, puis le retour Échap
aux six cartes. Les profils existants, l’historique et l’accès Wi-Fi de l’iPhone
restent visibles. Les cartes exposent explicitement le trait de bouton.

Paquet dédié : `build/battery-cards/MacCare.app`, identité MacCare Dev, lancé avec
`-battery.protection.resume NO` pour la vérification visuelle. Les empreintes
des exécutables de `/Applications/MacCare.app` et
`/Applications/MacCare Dev.app` sont inchangées avant/après. Aucune activation
de protection, mise à jour d’assistant, décharge, programmation ou modification
Wi-Fi n’est exécutée pour cette QA.

Lors de la campagne visuelle initiale, l’assistant système retournait « délai de
réponse dépassé » ; les commandes de charge étaient donc désactivées. La cause
et sa correction après validation de l’interface sont suivies séparément dans
[la récupération de l’assistant](helper-registration-recovery.md). La feuille de
diagnostic est contrôlée visuellement, pas comme preuve d’un diagnostic réussi.
Le fonctionnement matériel, tous les réglages actifs, une campagne VoiceOver
complète, les textes agrandis et toutes les tailles de fenêtre ne sont pas
revendiqués. L’accès Outline reste en attente dans la note dédiée.
Les journaux sont dans `build/battery-cards-qa/`.
