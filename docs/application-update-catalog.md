# Catalogue hybride de mises à jour des applications

État au 9 novembre 2026 : **développement local non livré**. État de travail
sur `codex/apple-device-batteries`, base de départ `d2c5c8bd108520526472e5442956b40fa2f97bf3`.
Les travaux préexistants de la sonde batterie ne font pas partie de cette
évolution. Aucun push, merge, tag, publication ou installation quotidienne.

## Fonctionnement

Applications → Mises à jour dispose d’une source « Catalogue d’applications ».
Elle consulte le JSON public https://formulae.brew.sh/api/cask.json sans installer
Homebrew et sans exécuter les recettes Ruby. Le catalogue consulté pendant la QA
contient 7 822 fiches (19 399 001 octets). **Ce nombre n’est pas un nombre
d’applications effectivement prises en charge** : plusieurs fiches désignent
une variante, une police, un paquet ou une version non comparable.

La correspondance exige à la fois le nom exact du paquet `.app` et son
identifiant de bundle, référencé par les métadonnées `uninstall.quit` ou un
chemin exact de préférences `zap.trash`. Ces champs sont lus comme des données ;
aucune action uninstall/zap n’est exécutée. Une correspondance multiple est
écartée. Les éditions App Store restent gérées par mas embarqué. Les variantes
`@`, fiches désactivées/dépréciées et versions non numériques sont écartées.
Les plateformes et contraintes macOS publiées sont respectées ; les variations
spécifiques à la plateforme sont appliquées avant comparaison. Pour les versions
composites `version,build`, seule la version marketing est comparée. Les versions
déjà égales ou supérieures ne sont jamais proposées comme mises à jour.

Le fichier `OfficialGitHubApplication.swift` constitue le registre d’exceptions
officielles contrôlées. Sa première entrée est **ArtCraft Launcher**,
`ai.storyteller.artcraft-launcher`, dépôt `storytold/craft-launcher`. Il consulte
`releases/latest`, exclut brouillons/préversions et exige une archive macOS
universelle publiée. La page de la version est construite à partir du dépôt
contrôlé. La version complète `ArtCraftLauncherVersion` est lue lorsqu’elle est
présente pour éviter de comparer une préversion comme une édition stable.
La compatibilité macOS future d’ArtCraft n’est pas déduite d’un numéro de version ;
la page officielle reste à consulter avant installation.

Le flux Sparkle spécifique NetNewsWire reste conservé et prioritaire. Les
résultats du catalogue correspondant à une ligne Homebrew ou à la même app
NetNewsWire sont regroupés. Les anciens contrôles CLI Homebrew, mas et macOS
restent disponibles. Le compteur et les deux vues de mises à jour incluent la
nouvelle source. Le bouton **Accéder au téléchargement** ouvre la page de
l’éditeur (catalogue) ou la release officielle (ArtCraft). Aucune archive n’est
téléchargée et aucune installation n’est déclenchée par cette vérification.

## Réseau et limites

La vérification complète est à la demande. Le téléchargement du catalogue ne
transmet pas l’inventaire : les rapprochements sont locaux. Les requêtes GitHub
concernent seulement les exceptions installées ; elles utilisent l’accès public,
sans token utilisateur. Les réponses sont vérifiées (HTTPS, HTTP 200, taille),
avec délai de requête de 30 secondes et cache HTTP normal de URLSession.
Une source inaccessible produit un contrôle incomplet, en conservant les
résultats des autres sources. Aucun service distant MacCare ou stockage de
l’inventaire n’a été ajouté.

La reconnaissance est volontairement prudente : paquet renommé, installation
hors des deux dossiers Applications déjà recensés par MacCare, édition ambiguë,
schéma de version particulier ou identifiant absent peuvent empêcher un résultat.
Le catalogue communautaire peut être en retard ou contenir des métadonnées
imparfaites. Les nouvelles versions majeures de macOS nécessitent un nom de
plateforme connu ; sinon le contrôle signale une erreur. Le catalogue ne promet
pas la mise à jour gratuite d’une édition sous licence. Pas de lecture générique
d’un `SUFeedURL` arbitraire : seules les sources officielles enregistrées sont
consultées directement.

## Validation

29 tests ciblés réussis : 24 XCTest (dont 11 nouveaux) et 5 Swift Testing App
Store. Ils couvrent identité, paquet, canaux, égalité/downgrade, contraintes
macOS/architecture, variations, éditions ambiguës, préférences exactes, doublons,
release officielle, absence de réseau pour les apps App Store et échec partiel.
Le test réseau optionnel vérifie les API réelles : anciennes installations
simulées Cursor 1.0 → 3.29.9 et ArtCraft 0.1.0 → 0.16.1. ArtCraft n’est pas
installé sur ce Mac : sa validation n’est pas une observation d’installation.

La vérification réelle de l’inventaire de ce Mac détecte onze mises à jour :
AFFiNE, Bitwarden, ChatGPT, CleanShot X, Cursor, Figma, Firefox, Google Chrome,
Helium, Kimi et Opera. Les versions exactes sont dans
`build/native-updates-tests.log` (`LIVE_INSTALLED_QA`).

Commande de test (réseau facultatif, explicite) :

```sh
MACCARE_UPDATE_NETWORK_QA=1 swift test --package-path app \
  --scratch-path build/swift-tests --build-system native --arch arm64 \
  -Xlinker -L"$PWD/core/target/release" \
  --filter 'NativeApplicationUpdatesTests|ApplicationUpdatePresentationTests|ApplicationsOverviewTests|NetNewsWireUpdatesTests|AppStoreUpdatesTests'
```

Composants : `NativeApplicationUpdates.swift`, `HomebrewApplicationCatalog.swift`,
`OfficialGitHubApplication.swift`, `UpdatesModel.swift`,
`ApplicationUpdatePresentation.swift`, `ApplicationsAnalysisModel.swift`,
`ApplicationsUpdatesManager.swift`, `UpdatesView.swift` et
`NativeApplicationUpdatesTests.swift`.

Sources de référence :
[API Homebrew](https://formulae.brew.sh/docs/api/),
[release officielle ArtCraft](https://github.com/storytold/craft-launcher/releases/latest),
[identité macOS ArtCraft](https://github.com/storytold/craft-launcher/blob/main/packaging/macos/Info.plist.in).

Build Release arm64 et packaging `build/native-updates/MacCare.app` réussis ;
identité **MacCare Dev 0.2.16 (7)**, Apple Development, sans flux de distribution,
signature profonde stricte valide. QA dans ce chemin absolu avec
`-battery.protection.resume NO` : Applications → Analyser → Voir les mises à jour,
**12 résultats = 11 catalogue + 1 Homebrew**, App Store et NetNewsWire sans
mise à jour. Détail Cursor **3.12.30 → 3.29.9**, source Catalogue Homebrew,
bouton natif « Accéder au téléchargement » et état des quatre sources vérifiés
dans l’arbre d’accessibilité et visuellement à 1436 × 784 points. Le bouton n’a
pas été cliqué ; sa destination est vérifiée dans les données et tests. Pas de
campagne complète clavier/VoiceOver, Intel ou anciens macOS. La fenêtre Dev
reste ouverte sur le détail Cursor pour revue.

La copie quotidienne `/Applications/MacCare.app` conserve son SHA-256
`78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.
Les travaux batterie préexistants et les autres copies de développement
sont préservées. Preuves : `build/native-updates-validation.json`,
`build/native-updates-tests.log`, `build/native-updates-final-build.log`.

Outline synchronisé et relu le 9 novembre 2026 : index MacCare et chapitres
04, 07, 08 et 11, ancien contenu et emplacement conservés. Preuve :
`build/native-updates-outline-validation.json`.

## Préparation de la prochaine release — 9 novembre 2026

À la demande de Gregory, le catalogue hybride, ses tests et la documentation
sont enregistrés dans Git sur `codex/apple-device-batteries`. Le site et ses
guides sont déjà publiés ; la fonction de l’application reste non livrée.
La fusion de cette branche et la publication d’une nouvelle version restent
à effectuer. Aucun changement de version ni remplacement de la copie quotidienne.
