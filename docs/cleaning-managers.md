# Gestionnaires Nettoyage standardisés

Disponible depuis [MacCare 0.2.8 (build 10)](https://github.com/M0okz/maccare/releases/tag/v0.2.8), publiée le 6 novembre 2026
(heure de Paris). Installation de cette version vérifiée dans
`/Applications/MacCare.app` via Sparkle, depuis 0.2.6 (8). Le paquet installé
correspond au binaire public signé et notarié. Les validations de développement
ci-dessous restent datées et conservent leurs limites.

Les six sous-vues de Nettoyage réutilisent le cadre des gestionnaires de
Performances : panneau blanc intégré, en-tête « Gestionnaire Nettoyage »,
Retour (Échap), sélecteur d’outil, navigateur à gauche, contenu à droite et
actions en bas. Le choix des outils respecte l’option développeur.

`CleaningDetailPanel` regroupe les résultats du Smart Scan, le nettoyage par
catégorie, les corbeilles, le nettoyage système, les caches de développement
et les simulateurs. Retour et changement d’outil sont désactivés pendant
les analyses/lectures et suppressions en cours.

`CleaningManagerLayout` partage les deux colonnes et la barre inférieure.
Les descriptions restent intégrales et les catégories longues peuvent
occuper deux lignes. Les lignes d’actions adaptatives évitent de comprimer
les commandes des résultats, des catégories et des caches développeurs.
Les modèles, règles, présélections et confirmations de suppression restent
ceux des outils existants.

Les sources concernées sont `CleaningDetailPanel`, `CleaningManagerLayout`,
`Shell`, `ContentView`, `SmartScanView`, `TrashView`, `SystemCleanView`,
`DevJunkView` et `SimulatorsView` dans `app/Sources/MacCare`.

Validation initiale du 6 novembre 2026, sur la base `8868649` : compilation
Release arm64, paquet Dev signé, dix tests Nettoyage/navigation, contrôle des
six outils à 1200 × 720, analyse seule d’une catégorie et Smart Scan avec
résultats réels, changement de groupe, désélection et Retour par Échap.
Aucune suppression utilisateur ni commande batterie pendant cette QA.
Preuves locales : `build/cleaning-manager-validation/validation.json`.

La QA a utilisé un identifiant distinct, sans accès complet au disque ni
accès à l’assistant privilégié. Les suppressions et journaux privilégiés n’ont
pas été exécutés. VoiceOver, Voice Control, texte agrandi, Réduire les animations
et les autres tailles de fenêtre restent à vérifier. La copie utilisateur
est distincte des paquets de développement ; l’intégration dans `main` ne
constitue pas une nouvelle release ni une installation.

Après intégration avec les alertes dans la PR nº 4 et mise à jour avec `main`,
les neuf fichiers d’interface correspondent aux empreintes de la QA décrite
ci-dessus. La suite complète de la branche passe : 212 XCTest et 226 tests
Swift Testing. Les contrôles de compilation et packaging de la PR complètent
cette validation sans lancer de suppression ni remplacer l’app utilisateur.

## Relancer depuis le bilan — correction Dev du 6 novembre 2026

Après une analyse, « Relancer l’analyse » dans le bilan Nettoyage revient désormais
à l’introduction avec son bouton « Analyser ». Le moteur ne redémarre qu’au clic
explicite sur ce dernier. Avant la correction, le bouton appelait directement la
même action que le premier démarrage et revenait au bilan après le nouveau scan.

`SmartScanModel.prepareForNewScan()` remet à zéro les résultats et sélections de
la session, la progression, les messages et le compte rendu. Il annule l’ancienne
tâche et invalide sa génération pour ignorer tout résultat tardif. Le dernier
bilan complet mémorisé (date et volume sûr) est conservé. Une suppression en cours
bloque cette remise à zéro, comme le bouton déjà désactivé. La vue désactive aussi
le mode d’accès direct aux outils pour afficher effectivement l’introduction.
Le premier lancement depuis les outils sans résultat garde son action d’analyse.

Les préférences sont injectables dans SmartScanModel pour les tests ; la production
conserve UserDefaults.standard et les mêmes clés, sans migration de profil ni
changement des exclusions. Deux tests de régression sur des fixtures temporaires
vérifient le retour sans relance, la conservation du bilan et les résultats tardifs.
Ils échouaient avec l’ancienne action puis passent après correction. Avec les
suites Nettoyage, profils et navigation, 15 tests ciblés passent.

Correction locale non publiée sur `codex/tray-storage-battery-details`, après
`7bcdedb`. Le paquet Dev est `build/cleaning-restart/MacCare.app` ; la copie Dev
installée conserve le chemin `/Applications/MacCare Dev.app`. La release publique
0.2.10 et la copie quotidienne `/Applications/MacCare.app` ne sont pas modifiées.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).
