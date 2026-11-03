# Releases MacCare pour Apple Silicon

## Deux chaînes distinctes

`CI` exécute les tests Rust et Swift, les contrôles des outils de release et génère
un DMG arm64 téléchargeable comme artefact `MacCare-arm64-ci`. Ce DMG de validation
peut être signé ad hoc ; il ne doit pas être présenté comme une distribution notariée.
Les pull requests n’ont accès à aucun secret de signature.

Les deux jobs utilisent des runners macOS Apple Silicon. Les règles privilégiées
du moteur utilisent notamment les flags de fichiers macOS ; leur validation ne
doit pas être remplacée par un succès partiel sur un hôte Linux.

`Release macOS` démarre sur un tag `vMAJEUR.MINEUR.CORRECTIF` ou manuellement avec un
tag existant. L’exécution manuelle conserve les artefacts sans publier, sauf si
`publish` est activé. Le tag doit correspondre à `CFBundleShortVersionString` dans
`app/Info.plist`. Le numéro interne Sparkle est le `github.run_number` de cette chaîne,
strictement numérique et croissant. Un tag publié ne doit pas être réutilisé.

## Secrets et variable GitHub

À configurer dans le seul dépôt de l’application :

| Nom | Type | Contenu |
| --- | --- | --- |
| `MACCARE_CERTIFICATE_P12` | Secret | Certificat Developer ID Application et clé privée, export PKCS#12 encodé en base64 |
| `MACCARE_CERTIFICATE_PASSWORD` | Secret | Mot de passe de cet export |
| `MACCARE_NOTARY_KEY_P8` | Secret | Clé privée d’API Apple autorisée pour notarytool |
| `MACCARE_NOTARY_KEY_ID` | Secret | Identifiant de cette clé Apple |
| `MACCARE_NOTARY_ISSUER_ID` | Secret | Issuer ID associé |
| `MACCARE_SPARKLE_PRIVATE_KEY` | Secret | Graine Ed25519 de 32 octets encodée en base64 |
| `MACCARE_SPARKLE_PUBLIC_KEY` | Variable | Clé publique Ed25519 correspondante, encodée en base64 |

La notarisation accepte aussi les secrets `MACCARE_APPLE_ID`, `MACCARE_APPLE_TEAM_ID`
et `MACCARE_NOTARY_PASSWORD` (mot de passe spécifique d’application Apple) à la place
des trois secrets de clé API. Une configuration API complète est prioritaire.

Les secrets ne sont jamais intégrés à l’app, au flux ou aux artefacts. Le certificat
est importé dans un trousseau temporaire du runner et retiré en fin d’exécution,
y compris après échec. Les clés Sparkle publique et privée sont comparées avant
signature. Aucun certificat ni clé n’est exporté ou envoyé à GitHub par les scripts locaux.
Les étapes de build et de tests ne reçoivent pas les secrets de signature et sont
terminées avant l’importation du certificat dans le trousseau du runner.

Pour créer la clé Sparkle dans un trousseau de développement :

```sh
swift package --package-path app resolve
app/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account org.maccare.app
```

La sauvegarde sécurisée de cette clé et son transfert vers le secret GitHub sont
des opérations séparées. Ne jamais committer ni afficher sa valeur privée.

## Ordre des opérations de distribution

1. Build officiel arm64 et tests ; injection de la version, du numéro interne,
   de la clé publique et du flux HTTPS public dans le paquet avant signature.
2. Signature des outils Sparkle, de l’assistant et de l’app avec Developer ID,
   runtime durci et entitlement d’Automatisation de l’app.
3. Notarisation de l’app, agrafage et validation de son ticket, contrôle Gatekeeper.
4. Création du DMG à partir de ce paquet déjà agrafé, sans reconstruire ni modifier l’app.
5. Signature, notarisation et agrafage du DMG ; vérification de l’image et du ticket
   de l’app réellement embarquée.
6. Calcul du SHA-256 et signature Ed25519 du DMG final ; génération et signature du
   flux `appcast.xml`. Le flux exige Apple Silicon et macOS 13.0.0 au minimum.
7. Création d’une release brouillon, dépôt des seuls artefacts vérifiés, puis publication.

Les notes sont prises dans `docs/release-notes/<version>.md` lorsqu’elles existent,
pour conserver les disponibilités et limites du matériel dans la release et le flux
Sparkle. À défaut, le workflow génère les notes depuis GitHub.

Le build de l’application sélectionne explicitement `--build-system swiftbuild`,
disponible avec Swift 6.2 et suivants. Le moteur SwiftPM natif de certains Xcode
plus anciens n’émet pas les constantes App Intents nécessaires au packaging.
Le choix explicite conserve les mêmes artefacts en local et sur le runner GitHub ;
la cible d’exécution de l’app reste macOS 13. L’architecture est fixée explicitement
à celle du moteur Rust (`--arch arm64` sur les runners de distribution), car
Swift Build peut sinon tenter de lier un exécutable Intel avec la bibliothèque
Rust Apple Silicon.

Les tests utilisent le moteur `--build-system native` dans un dossier séparé
(`--scratch-path build/swift-tests`). Le lanceur de tests de Swift Build livré avec
Xcode 26 ne retrouve pas le framework binaire Sparkle dans cette configuration.
Les suites restent complètes ; le dossier distinct préserve les produits Release
et les constantes App Intents destinés au packaging. Aucun chemin de chargement
ni contrôle de signature de l’application distribuée n’est modifié.

Le packaging résout le dossier des produits avec `swift build --show-bin-path`
et les mêmes paramètres de moteur, configuration et architecture. Il ne dépend
pas du lien de commodité `.build/release`, absent sur certaines versions de SwiftPM.
Les constantes App Intents sont sélectionnées depuis la carte de sortie du module
MacCare, pour la configuration et l’architecture attendues. Les noms de dossiers
internes des cibles changent entre Xcode ; les constantes manquantes ou plusieurs
produits de module ambigus bloquent le packaging.

Le flux stable est
`https://github.com/M0okz/maccare/releases/latest/download/appcast.xml`.
Chaque flux contient la dernière version ; les DMG et signatures des anciennes
versions restent dans leurs releases. Une future hausse du minimum macOS devra
conserver dans le flux la dernière version compatible avec les systèmes précédents.

Les signatures du flux et du DMG sont requises par l’app. Les installations
automatiques silencieuses et le profilage Sparkle sont désactivés. La terminaison
de MacCare conserve son parcours existant de restauration de la protection batterie.
L’assistant reste géré par SMAppService ; aucune installation privilégiée distincte
n’est ajoutée par le DMG ni par le module de mises à jour.

## Validation avant la première diffusion

La réussite du workflow ne remplace pas l’essai sur un Mac : vérifier l’installation
dans Applications, l’Automatisation sous runtime durci, les consentements macOS,
l’activation facultative de l’assistant, puis une mise à jour réelle entre deux
versions distribuées. La validation de la première mise à jour reste nécessaire
tant que deux releases signées ne sont pas disponibles.
