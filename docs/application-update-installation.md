# Installation des mises à jour depuis le gestionnaire Applications

## Livraison 0.2.22 — 10 novembre 2026

L’installation depuis Applications est **publiée dans [MacCare 0.2.22 (build 24)](https://github.com/M0okz/maccare/releases/tag/v0.2.22)**, après fusion de la PR #30. Le tag `v0.2.22` vise `b73a43d45154c9adcf4087039cd90a2430e067c9`. Les CI de branche, PR et fusion ainsi que le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42716751129) réussissent. Ce statut remplace les mentions de développement non livré de ce correctif ; les preuves et limites datées restent conservées. La publication ne remplace pas les copies installées. Voir [la validation publique et les limites](release-integration-0.2.22.md).

## État de développement antérieur

9 novembre 2026 — **en développement, non publié** sur
`codex/application-update-installation`, base `c682107` (MacCare 0.2.20).
La 0.2.20 publiée ne contient encore que la détection et les liens externes.
Cette évolution corrige ce périmètre incomplet : le bouton principal devient
**Mettre à jour**, avec progression, erreur ou résultat d’installation.

## Parcours

- **Sparkle dans l’application cible** : MacCare ouvre le vrai panneau de mise
  à jour avec ses nouveautés, téléchargement et installation. Le paquet cible
  est à la fois `hostBundle` et `applicationBundle` ; MacCare ne se désigne pas
  comme application à quitter ou relancer. Le flux HTTPS et la clé Ed25519 sont
  ceux de l’app installée. Ses préférences ne sont pas réécrites.
- **Homebrew** : un cask enregistré ne passe par `brew upgrade --cask --greedy`
  que si son lien dans Caskroom désigne exactement la copie sélectionnée. Une
  seconde copie du même logiciel ne doit pas être mise à jour par erreur.
  Les actualisations normales des métadonnées sont laissées à Homebrew lors de
  cette action explicite. L’analyse reste en lecture seule avec son environnement
  sans mise à jour automatique de Homebrew. MacCare n’installe pas Homebrew.
- **App Store** : l’identifiant numérique `adamID` est conservé depuis la lecture
  de `mas outdated`. Une action met à jour ce seul identifiant avec le mas embarqué.
  macOS demande l’autorisation administrateur dans son propre dialogue. Le mot
  de passe n’entre jamais dans MacCare. Le composant est copié dans un dossier
  privé appartenant à root, puis vérifié Developer ID, identifiant `org.maccare.mas`
  et équipe MacCare avant l’exécution de cette copie. Une substitution du fichier
  source après validation ne peut donc pas devenir du code exécuté en root.
  La phase privilégiée suit `mas update --force` pour ce seul identifiant déjà
  sélectionné par la lecture utilisateur, avec `MAS_NO_AUTO_INDEX=1` pour ne pas
  réindexer Spotlight. Le dossier est nettoyé à la sortie. Cette action est désactivée dans le paquet
  Dev Apple Development ; elle demande la distribution signée Developer ID.
- **Autres DMG et ZIP** : MacCare télécharge directement l’archive décrite par
  le catalogue ou le dépôt officiel, prépare l’app, puis remplace le paquet
  existant. Homebrew n’est pas requis. L’API de métadonnées d’un cask peut être
  consultée au clic pour compléter une ancienne ligne CLI, après rapprochement
  de l’identifiant et du nom du paquet installé.
- **PKG** : l’archive est téléchargée et sa signature d’installateur vérifiée,
  puis ouverte dans l’installateur macOS. L’interface demande de terminer ce
  parcours puis de vérifier la version réellement installée. Ouvrir un PKG ne
  devient jamais à lui seul un résultat « installé ». Le téléchargement reste
  nécessaire à cette installation en attente et est retiré après vérification.

Une app ouverte est quittée seulement après le choix **Quitter et mettre à jour**.
La demande est normale, sans arrêt forcé ; si un enregistrement ou une fermeture
reste en attente, la mise à jour s’interrompt. Sparkle conserve son propre parcours
de fermeture. Une seule opération d’installation est engagée à la fois.
L’annulation est disponible avant l’étape d’installation, pas pendant un remplacement.

## Vérifications avant et après remplacement

La destination doit être une app déjà présente sous `/Applications` ou le dossier
Applications de l’utilisateur. Un lien symbolique et MacCare lui-même sont refusés.
La nouvelle app doit avoir le même identifiant, une version supérieure à celle
installée et au moins celle annoncée, un système et une architecture compatibles,
une signature valide et la même équipe de signature. Gatekeeper doit accepter
l’app téléchargée. Le SHA-256 est contrôlé lorsqu’il est fourni.

Les redirections de téléchargement restent HTTPS ; ni inventaire d’apps ni
identifiants d’authentification ne sont envoyés au serveur de téléchargement.
Les archives sont préparées dans un dossier privé. Les chemins absolus ou `..`
sont refusés pour les ZIP ; l’extraction utilise bsdtar et sa protection contre
l’écriture à travers un lien qui sort du dossier. Une image disque reste montée
en lecture seule et sans ouverture Finder, puis est détachée avant nettoyage.

La destination et les deux signatures sont revérifiées après une éventuelle
autorisation macOS. L’API de remplacement atomique de FileManager conserve les
permissions de la destination ; les données et préférences hors du paquet ne
sont pas supprimées. L’inventaire et NetNewsWire relisent le plist sur disque,
car un `Bundle` peut garder l’ancienne version en cache dans le même processus.
Après confirmation du résultat, les sources sont analysées à nouveau.

## Contrôles réalisés et limites

Les tests ciblés vérifient les destinations, identités, versions, empreintes,
commandes et échappements, l’outil App Store non signé refusé avant exécution,
les archives avec lien d’évasion, les copies Homebrew distinctes et les callbacks
Sparkle. Un vrai DMG MacCare signé/notarié a mis à jour une copie possédée 0.2.19
vers 0.2.20, avec échec au mauvais SHA-256 sans modification de l’ancienne app,
puis remplacement réussi et fichier de préférences conservé. La fixture seule
permet l’identifiant de MacCare ; la politique de production continue de le refuser.
Un second contrôle a effectué **PhotoCraft 0.21.0 → 0.22.0** avec les vrais
DMG officiels Storytold sur une autre copie isolée : SHA-256 officiels,
signature de l’éditeur, Gatekeeper, remplacement et préférences conservées.
Aucune app personnelle n’est remplacée par ces tests ; les deux copies possédées
et leurs téléchargements sont nettoyés à la fin de chaque cas.
Les tests réseau volumineux restent explicitement optionnels en CI.

359 XCTest exécutés lors de la passe complète (trois tests réseau optionnels
ignorés, aucun échec) et 259 Swift Testing réussis. Build Release arm64 et paquet
Dev signé vérifiés. Le bouton activé **Mettre à jour** est visible dans le vrai
gestionnaire, sur une mise à jour Bitwarden du catalogue. Aucune mise à jour
réelle d’une app quotidienne n’a été lancée pendant cette vérification native.

Les parcours Homebrew et App Store ne sont pas revendiqués exécutés sur les apps
personnelles. Le dialogue d’autorisation administrateur, une vraie session
Sparkle tierce et une installation PKG complète restent à valider séparément.
Pas de campagne VoiceOver complète ni d’exécution sur les anciens macOS.
Les apps sans archive compatible, sans identité vérifiable ou gérées par un
installateur spécialisé peuvent demander leur mécanisme éditeur.

Preuves : `build/application-update-install-qa/update-action.png`, journaux
`build/application-update-install-*.log`. Copie de vérification :
`build/application-update-install-verified/MacCare.app`. La Dev ouverte pour
la capture utilise le même code d’interface et les mêmes parcours activés ;
le dernier ajustement App Store ne concerne que la distribution signée.

Sources : [Sparkle — mises à jour de bundles externes](https://sparkle-project.org/documentation/bundles/),
[Apple — autorisation de remplacement](https://developer.apple.com/documentation/appkit/nsworkspace/authorizationtype/replacefile),
[mas](https://github.com/mas-cli/mas), [API du catalogue Homebrew](https://formulae.brew.sh/docs/api/).

## Livraison 0.2.23 — 10 novembre 2026

**Livré dans [MacCare 0.2.23 (build 25)](https://github.com/M0okz/maccare/releases/tag/v0.2.23)**, tag sur `a3c3f98f646fa27202607b47c6879969ca6eb72b` après fusion des PR #31 et #32. Le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42789605501) et les CI du code publié réussissent. Ce statut remplace les mentions de préparation/non livré de ces deux correctifs ; les validations historiques restent datées. Le rappel utilise une barre gérée seulement par SwiftUI ; l’analyse et le staging lisent les architectures sans lipo ni demande d’outils Xcode. [Vérifications publiques et limites](release-integration-0.2.23.md). La publication ne remplace pas les copies installées.


## Correctif ZIP et iStat Menus — préparation 0.2.24, 10 novembre 2026

Branche `codex/complete-zip-listing`, non livrée à ce stade. Le runner conservait
seulement les 128000 derniers octets de sortie de zipinfo. La liste officielle
d’iStat Menus 7.50.2 compte 358301 octets et 3068 entrées : sa coupure fabriquait
un chemin commençant par `/`. Le test de reproduction échouait sur 854 entrées
et un faux chemin absolu.

Le mode de lecture complète, limité à 16 Mio pour zipinfo, refuse explicitement
un dépassement au lieu de rendre des données partielles. La sortie est drainée
jusqu’à la fin même au-delà de cette limite pour éviter un blocage du processus.
Les journaux ordinaires conservent leur limite de 128000 octets. Les chemins
absolus, traversées `..`, signatures, Gatekeeper, empreintes et architectures
restent contrôlés. Une archive adversaire place une traversée avant plus de
128 Ko d’entrées pour vérifier qu’elle n’est jamais perdue.

Le build officiel 2394 du bundle `com.bjango.istatmenus` déclare encore 7.50.
Une exception exacte pour ce couple version/build reconnaît 7.50.2, utilisée
pour l’inventaire, la validation et le contrôle après installation. Aucun autre
build ou bundle n’est interprété ainsi. SHA-256 du ZIP officiel :
`8c633ede51c431e0e9dcba864a2ac3499e9dc1c2ff5d849450b2b1e09c7d3d92`.
Le vrai remplacement d’une copie isolée 7.50 (2355) vers 7.50.2 (2394) passe :
signataire `Y93TK974AT`, Gatekeeper, préférences de test conservées et absence
de nouvelle proposition de la même version. Ni iStat ni ses helpers n’ont été
lancés ; la gestion des agents par l’éditeur après lancement reste hors de ce test.

Sources : [archive officielle Bjango](https://cdn.istatmenus.app/files/istatmenus7/versions/iStatMenus7.50.2.zip),
[fiche Homebrew](https://formulae.brew.sh/api/cask/istat-menus.json).
La confirmation du correctif sur le second Mac reste à faire.

Validation locale du correctif : build Release arm64 réussi, 365 XCTest exécutés
(5 parcours optionnels ignorés), 269 Swift Testing et 19 tests Python réussis.
Le parcours iStat optionnel est exécuté séparément avec les archives officielles ;
les tests de lecture complète, de dépassement de limite et de traversée ZIP passent.
Le contrôle d’absence d’outils de développement au runtime passe également.


## Livraison 0.2.24 — 10 novembre 2026

**Livré dans [MacCare 0.2.24 (build 26)](https://github.com/M0okz/maccare/releases/tag/v0.2.24)**,
tag sur `4b7372b08ed5ac8bb70eab8c9e23ae076b78a47e` après fusion de la PR #33.
Les CI de branche, de PR, après fusion et le workflow officiel réussissent.
Ce statut remplace les mentions de préparation/non livré du correctif ZIP et
d’iStat ci-dessus ; les validations historiques restent datées.
[Vérifications publiques et limites](release-integration-0.2.24.md).
La publication ne remplace pas les copies installées.

## Préparation 0.2.25 — 10 novembre 2026

Le correctif du contexte utilisateur App Store et les nouvelles alertes de version
sont en développement dans `codex/app-store-session-context`, non livrés à cette
étape. Voir [le diagnostic Bitwarden et ses limites](app-store-updates.md) et
[les notifications locales et la position du rappel](app-update-notifications.md).
Les contrôles de signature et le staging App Store ne sont pas relâchés.
