# Installation des mises à jour depuis le gestionnaire Applications

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
