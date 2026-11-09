# Sous-vues des gestionnaires

## État de préparation

Corrections validées en Dev le 9 novembre 2026, préparées pour la prochaine
release sur `codex/apple-device-batteries`. Elles ne sont pas encore publiées
dans une release et ne remplacent pas l’application quotidienne installée.

## Composition partagée

Les gestionnaires conservent un panneau clair intégré à la fenêtre, un en-tête
avec retour, un navigateur à gauche, le détail à droite et les actions en bas.
`ManagerBrowserLayout` fournit les colonnes et la séparation de la barre
d’action pour Nettoyage, l’optimisation PNG, la santé des disques et les accès
directs aux mises à jour.

- **Applications — démarrage** : réutilise `PerformanceStartupManager`, avec
  les catégories « À la connexion » et « En arrière-plan », comme Performances
  et Mes outils.
- **Accès directs Applications** : les destinations de désinstallation et de
  mises à jour passent par `ApplicationsDetailPanel`. Le retour mène au bilan
  Applications. L’accès direct aux mises à jour conserve toutes les sources,
  y compris les formules Homebrew et macOS.
- **Optimisation PNG** : les images choisies apparaissent dans le navigateur ;
  le détail présente leur aperçu Quick Look, leur état et les tailles de
  l’original et de la copie. Le choix du dossier, l’arrêt après l’image en cours
  et l’accès aux copies restent dans le même parcours. Les originaux sont
  conservés. Le retour est désactivé pendant le traitement.
- **Santé des disques** : le navigateur présente les volumes locaux. Le détail
  affiche le diagnostic ; l’actualisation et la date du relevé sont regroupées
  dans la barre inférieure. La lecture reste seule, sans écriture sur le disque.
- **Feuilles secondaires** : `ManagerSheetStyle` partage l’apparence claire
  entre Activité récente, le diagnostic de compatibilité Batterie et les
  confirmations des outils.

Les modèles de nettoyage et d’optimisation, les règles de sélection et les
confirmations d’action sont conservés. À cette étape, les écrans spécialisés Batterie et
Espace disque ainsi que la fenêtre native Réglages gardaient leur navigation.
La refonte Batterie par blocs du 9 novembre, en développement sur
`codex/battery-cards`, réutilise désormais ce cadre intégré pour ses six
sous-vues ; voir [son organisation et ses vérifications](battery-cards.md).

## Validation

- Compilation Release arm64 et signature profonde stricte du paquet Dev réussies.
- 17 tests XCTest et 9 tests Swift Testing ciblés réussis : navigation, bilan
  Applications, présentation des mises à jour, Nettoyage, santé des disques et
  optimisation PNG.
- Contrôle natif du navigateur de démarrage, des deux catégories, du diagnostic
  disque terminé et des feuilles claires ; retour Échap vérifié.
- Optimisation native d’une fixture PNG de 16 555 octets vers une copie de
  214 octets, avec aperçu et résultat visibles. Original inchangé ; les tests
  vérifient aussi les pixels décodés et les métadonnées.
- Confirmation de réparation ouverte puis annulée, sans exécution. Copie de QA,
  préférences de QA et copie PNG temporaire supprimées après vérification.

Les accès directs Applications ont été contrôlés dans les sources et par la
compilation ; un retour depuis l’historique après une suppression réelle n’a
pas été exécuté. La campagne complète VoiceOver, les textes agrandis et la
taille minimale de fenêtre restent à vérifier. Aucune commande batterie,
activation d’assistant ou suppression de données utilisateur n’a été réalisée.
