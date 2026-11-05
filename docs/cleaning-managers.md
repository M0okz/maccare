# Gestionnaires Nettoyage standardisés

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
