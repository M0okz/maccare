# Stabilité du rappel de mise à jour

## Livraison 0.2.23 — 10 novembre 2026

**Livré dans [MacCare 0.2.23 (build 25)](https://github.com/M0okz/maccare/releases/tag/v0.2.23)**, tag sur `a3c3f98f646fa27202607b47c6879969ca6eb72b` après fusion des PR #31 et #32. Le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42789605501) et les CI du code publié réussissent. Ce statut remplace les mentions de préparation/non livré de ces deux correctifs ; les validations historiques restent datées. Le rappel utilise une barre gérée seulement par SwiftUI ; l’analyse et le staging lisent les architectures sans lipo ni demande d’outils Xcode. [Vérifications publiques et limites](release-integration-0.2.23.md). La publication ne remplace pas les copies installées.

## Historique du développement

10 novembre 2026 — correctif en développement, non encore publié.

Le rapport utilisateur porte sur MacCare 0.2.20 (22), macOS 27.2 et un Mac
Apple Silicon. L’exception arrive sur le thread principal environ une seconde
après le lancement, dans `NSObject._removeObserver:forProperty:` appelé par
`SwiftUI.AppKitWindowController.updateToolbarIfNeeded`. Il ne s’agit pas d’une
pile d’extraction d’archive ou d’une terminaison normale après installation.

## Cause reproduite et correction

`RootView` déclarait le rappel par `.toolbar`, tandis que `WindowConfigurator`
affectait aussi `window.toolbar` lorsqu’il était vide. Le groupe d’outils était
ajouté ou retiré selon la disponibilité d’une version et l’état de l’accueil.
SwiftUI et la configuration AppKit devenaient propriétaires de la même barre,
avec un cycle d’observation incohérent.

La sonde native compile les vrais composants de barre et de configuration de
fenêtre, avec des états contrôlés à la place des scans et de Sparkle. Avant le
correctif, elle plante avec le même enchaînement `removeObserver` puis
`updateToolbarIfNeeded` sur macOS 27.0.1. Après correction, quatre lancements et 640 transitions terminent sans cette
exception. Le passage est répété avec le vrai bouton et les composants de style
de production.

SwiftUI est désormais le seul propriétaire de la barre. L’élément du rappel a
un identifiant stable et reste déclaré quand le contenu devient invisible.
`WindowConfigurator` conserve le style de fenêtre et les migrations de taille,
sans réaffecter `window.toolbar`. Il est séparé de `Shell.swift` pour permettre
cette vérification native sans démarrer le moteur ni la protection de charge.
Le bouton conserve son action, son libellé, son aide et sa cible de 44 points ;
un rappel masqué pendant l’accueil est aussi retiré de l’accessibilité.

## Reproduire la vérification

Avec une session graphique macOS active :

```sh
bash app/Tests/WindowToolbarLifecycleTests/run.sh
```

La sonde exécute quatre lancements, en alternant l’état initial du rappel, et
640 changements d’affichage. Un processus qui plante ou qui n’atteint pas la fin
fait échouer la commande. `--compile-only` vérifie son assemblage sans lancer
l’interface. Les fichiers de travail et le domaine de préférences de la sonde
sont isolés ; aucune copie d’Applications, aucun compte App Store ni aucun
réglage de charge n’est modifié.

Les tests et preuves complètes sont enregistrés dans
`build/update-runtime-regression-qa/`. La confirmation sur le Mac du rapport,
une campagne VoiceOver complète et les autres versions de macOS restent à
vérifier. Le problème distinct de `lipo` doit être livré avec la lecture native
des architectures de la PR #31 ; installer Xcode n’est pas nécessaire.

## ArtCraft et absence d’outils de développement

La PR #31 est fusionnée sur main (`ec1d9d4`). La lecture native est reprise dans
ce correctif, sans modification du checkout parallèle qui la portait. La sonde
d’inventaire et l’audit des sources passent sans lanceur de développement.
Le test réseau opt-in `testArtCraft0161To0170WhenExplicitlyRequested` passe avec
les vrais DMG officiels : la copie possédée est remplacée de 0.16.1 à 0.17.0,
les contrôles de signature/Gatekeeper/empreinte et les préférences de test sont
préservés. Aucun lanceur ni jeu n’est exécuté et aucun compte utilisateur n’est
utilisé. Les archives et montages temporaires sont nettoyés par le test.

## Validation du correctif préparé en 0.2.23

361 XCTest passent sans échec, avec quatre cas réseau facultatifs ignorés dans
la passe générale ; 269 Swift Testing et 19 tests Python passent. Le cas réseau
ArtCraft a été exécuté séparément avec succès. La sonde graphique a aussi été
recompilée avec le vrai bouton et les styles de production : quatre lancements
et 640 transitions terminent sans exception. Sa compilation isolée est ajoutée
à la CI et à la chaîne officielle de release, avant l’accès aux clés.
