# Vérification de la branche d’accueil — 7 novembre 2026

Branche : `codex/dashboard-summary-cards`. Revue de l’ensemble depuis la base
`57300391cfe7972b1d88a32ad92d48edcc8060fe` jusqu’au commit utilisateur
`cf62181c33a4e7dd374f9f4c9507dce7e18f1925`. Les commits utilisateur `6cb1346`
(mas embarqué) et `cf62181` (PNG et santé des disques) sont conservés. Les
corrections de revue font l’objet d’un commit supplémentaire, sans réécriture.

## Revue et corrections

- **Standards** : le résultat PNG conservait la taille relevée à la sélection,
  même si le fichier avait changé avant le traitement. Le modèle affiche
  désormais la taille de l’entrée effectivement traitée, fournie par le moteur.
- **Spécification** : la limite de lecture de 12 secondes des commandes disque
  reposait sur SIGTERM, qu’un processus pouvait ignorer. Le lecteur impose
  désormais l’arrêt à l’échéance et retourne une indisponibilité. Les commandes
  restent fixes et en lecture seule.

Les deux régressions ont été reproduites par des tests en échec avant correction,
puis vérifiées après correction. L’ancien test de navigation Mes fichiers a
également été actualisé pour inclure l’outil PNG et vérifier son indépendance
vis-à-vis d’Espace disque. Les deux axes ont été relus après correction ; aucune
autre anomalie confirmée ne reste ouverte dans cette revue.

## Construction et contrôles

Le moteur Rust, le pont C et l’application Release arm64 ont été reconstruits
ensemble. Résultats finaux : **269 XCTest**, **242 Swift Testing**, **98 tests
Rust** et **19 tests Python** réussis ; deux tests Rust ignorés préexistants.
Les contrôles de frontière PowerUI n’appellent aucun setter natif ; les contrôles
positifs et négatifs des signatures Sparkle passent.

Le paquet `build/branch-integrated/MacCare.app` est signé Apple Development,
identifié MacCare Dev **0.2.11, build local 1**, sans flux Sparkle. Il comprend
mas 7.0.0, smartctl 7.5 r5714, oxipng 10.2.1 et leurs licences ; l’archive source
smartmontools correspond à l’empreinte du manifeste. Architecture arm64 et
signatures strictes vérifiées pour l’app, le helper, mas et smartctl. Le mas
embarqué fonctionne avec `PATH=/usr/bin:/bin` : aucune mise à jour App Store
détectée. Les outils ne dépendent pas de Homebrew.

## Vérification native dans la Dev installée

Installation uniquement dans `/Applications/MacCare Dev.app`, puis lancement
avec `-battery.protection.resume NO`. UUID compilé, empaqueté et installé
identique : `AEFFCA86-71BA-37F2-9A38-38A2A1EC7D96`. SHA-256 installé :
`4364c73422c92230d54da3cf0f7b9191bc6dea1c6764091e281be798d42ca940`.

- Accueil : bilan horizontal, Batterie compacte, texte Santé aligné et six
  tuiles Activité vérifiés visuellement dans la fenêtre native.
- Mes fichiers → Alléger des images : sélection native d’un PNG possédé,
  sélection du dossier, création et résultat **16 555 → 214 octets**. Empreinte
  de l’original inchangée. Ce ratio d’une fixture compressible n’est pas une
  promesse pour les images courantes.
- Outils → Santé des disques : lecture réelle du SSD APPLE SSD AP0512Q,
  aucune alerte rapportée, température observée 32–34 °C, endurance consommée
  4 %, zéro erreur d’intégrité. Détails dépliés et métriques visibles.
- Volet → Stockage interne : détail matériel et capacités présents ; le lien
  Voir la santé des disques rejoint le gestionnaire Outils.
- Applications → Analyser → Voir les mises à jour → État des sources : App
  Store indique aucune mise à jour détectée ; les deux résultats Homebrew sont
  identifiés séparément. Aucune installation de mise à jour effectuée.

La Dev a été relancée sur l’accueil après retrait des images de test. Le dossier
temporaire de test et la sauvegarde de l’ancienne Dev ont été supprimés après
validation. La copie quotidienne `/Applications/MacCare.app` reste en 0.2.8 (10),
signature vérifiée et SHA-256 inchangé :
`78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.

## État et limites

Cette intervention ne pousse aucun commit et ne crée aucune release ; elle
installe la Dev et ajoute les corrections locales au-dessus des commits
utilisateur. Aucune installation quotidienne ni notarisation de distribution.
Pas de campagne complète VoiceOver, clavier, Intel, anciens macOS, boîtiers USB
ou profils PNG variés. Aucune entrée App Store réelle disponible : les résultats
non vides sont couverts par les fixtures, pas par cette session native.

Preuves locales : `build/branch-integrated-qa/validation.json`, journaux de tests,
`red-tests.log`, `package-checks.json`, `package-provenance.json`,
`tool-runtime.json` et `native-runtime.json`.

## Version Dev actualisée après cette revue

La Dev installée porte désormais **0.2.12 (2)**, vérifiée dans sa fenêtre À propos.
Ce changement de métadonnées conserve les fonctionnalités et corrections revues
ci-dessus. Les références 0.2.11 (1) décrivent le paquet précédent. Voir
[la construction de la Dev 0.2.12](development-builds.md#numéro-de-version-actualisé--dev-du-7-novembre-2026).

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.
