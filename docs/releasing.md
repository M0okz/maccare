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
8. Mise à jour et redéploiement du site, qui n’est pas automatique : voir « À chaque
   release » dans [`site/README.md`](../site/README.md).

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

Avant signature, `app/release/configure_helper.py` reporte les versions réellement
injectées dans l’app et le canal de distribution dans le descripteur launchd de
l’assistant. Cela change sa configuration avec un nouveau build ou un autre
canal, en conservant les identifiants, la récupération et la politique de
démarrage. Les tests de release vérifient ces invariants et l’absence de
modification du descripteur source.

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

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.


## Publication 0.2.15 — 9 novembre 2026

Les correctifs d’icônes de helpers, de boutons natifs, de cache des mesures,
de température GPU M1 et d’interactions de la carte Espace disque sont publiés
sur [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15).
Le tag `v0.2.15` vise `d9969323a471e8517dc82dd9b9d81489f655d1b7`, après fusion de la
[PR #22](https://github.com/M0okz/maccare/pull/22). La branche
`codex/helper-process-icons` est supprimée localement et sur GitHub.

Les CI de branche, de PR et de fusion sont réussis, ainsi que le
[workflow de publication](https://github.com/M0okz/maccare/actions/runs/42538011402).
Les contrôles locaux incluent 285 XCTest, 247 Swift Testing, 19 tests de
packaging, les pilotes SMC/HID simulés sous ASan/UBSan et la cryptographie Sparkle.

Le DMG public téléchargé est vérifié : signatures Developer ID, tickets Apple
app/DMG, Gatekeeper, quatre exécutables arm64, version/canal du helper, licences
et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont valides
avec la clé publique de la copie quotidienne ; latest correspond à la release.
DMG : 15933396 octets ; SHA-256 `f6aabdffe2af849e94b60ea7bab3aa9fdee24a7ff36615455e768ec42f9a5d11`.

Le site public pointe vers ce paquet avec les mêmes version, taille et empreinte.
Le HTML HTTPS est identique aux sources et le conteneur est sain. Le seul fichier
HTML est remplacé de façon atomique en conservant ses droits ; la copie de
retour arrière est supprimée après vérification.

Les vérifications natives restent celles de la Dev 0.2.14 (13), à 1436 × 784 points.
La lecture réelle GPU du M1 Max, le survol à la souris physique, une campagne
complète VoiceOver, multi-écran et veille matérielle ne sont pas déclarés validés.
Aucune installation pendant la publication : la copie quotidienne reste en
0.2.8 (10), la Dev en 0.2.14 (13), empreintes et signatures préservées.
L’application distribuée n’a pas été lancée. Voir les
[notes et limites de cette version](release-notes/0.2.15.md).
Preuves : `build/release-0.2.15-qa/` ; les téléchargements, montages et outils de
travail temporaires sont nettoyés après les contrôles.


## Publication 0.2.16 — 9 novembre 2026

L’historique continu de l’activité, les chiffres lissés, les détails jusqu’à une
heure et les corrections du gestionnaire Applications sont publiés dans
[MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16). La [PR #23](https://github.com/M0okz/maccare/pull/23) est fusionnée ; le tag
`v0.2.16` vise `5109d72777bf859ddf80c4311d4039897664652c` et la branche de
préparation est supprimée localement et sur GitHub.

Les CI de branche, de PR et de fusion, puis le [workflow de publication](https://github.com/M0okz/maccare/actions/runs/42555458774), réussissent.
La validation inclut 294 XCTest + 247 Swift Testing et 19 tests de packaging,
les contrôles SMC/HID/PowerUI et les signatures Sparkle de la chaîne de CI.
Le DMG public téléchargé est signé Developer ID, notarié et agrafé, de même que
l’application embarquée. Gatekeeper accepte le paquet ; les quatre exécutables
propres à l’app sont arm64. Version et canal du helper sont cohérents.
Les signatures Ed25519 du flux et du DMG sont vérifiées avec la clé publique de
la copie quotidienne ; latest correspond à cette release.

DMG : 15978617 octets ; SHA-256 `00d5e17148e65f5fa5764812a5f05ed9e81ae60e95237c64a5ebc7b9e7819c25`.
Le site public porte les nouveaux liens, taille et empreinte ; HTML identique
aux sources après remplacement atomique avec propriétaire et droits préservés,
conteneur sain et copie temporaire de retour arrière supprimée.

Les contrôles natifs sont ceux des Dev 0.2.15 (18) et (19) : navigation et volet,
sélecteurs d’historique, zones vides des lignes et deux désinstallations factices
avec leurs préférences. Les limites de veille physique, collecte native d’une
heure, VoiceOver complet et mesure énergétique prolongée restent explicites.
Une application en cours n’est pas fermée automatiquement par le désinstalleur.
Aucune installation pendant cette publication : la copie quotidienne reste en
0.2.8 (10), la Dev en 0.2.15 (19), empreintes et signatures préservées.
L’app de distribution n’a pas été lancée. Voir les [notes de version](release-notes/0.2.16.md).
Preuves : `build/release-0.2.16-qa/`. Les téléchargements, montages et outils de
travail temporaires sont nettoyés après vérification.


## Publication 0.2.17 — 9 novembre 2026

[MacCare 0.2.17 (build 19)](https://github.com/M0okz/maccare/releases/tag/v0.2.17)
est publié après la PR #24, tag `v0.2.17` sur `22d72fa`. Les CI de branche,
PR et fusion, puis le workflow officiel `42630770167`, réussissent.
Le DMG public est vérifié : signatures Developer ID et Ed25519 du DMG/flux,
notarisation et agrafage app/DMG, Gatekeeper, cinq exécutables arm64 et helper
cohérent avec la distribution. La clé Sparkle correspond à celle de la copie
quotidienne ; latest est identique au flux signé de la release.

DMG : 16 049 174 octets, SHA-256
`f787279babc1d33b67fc236fa2b726d1be153294cb014d2bd2c9438d6b7b332f`.
Les copies installées sont préservées et la distribution n’est pas lancée.
Le site est redéployé et les dix fichiers HTML sont vérifiés identiques en HTTPS ;
conteneur sain, droits conservés et copies temporaires supprimées. Outline est
synchronisé puis relu après rétablissement des accès Homelab. Huit branches
locales intégrées et trois distantes sont fermées ; le chantier Batterie commencé
en parallèle est préservé. Voir [les preuves et limites](release-integration-0.2.17.md)
et [la clôture du site et de la documentation](release-0.2.17-completion.md).


## Livraison 0.2.19 — 9 novembre 2026

Publié dans [MacCare 0.2.19 (build 21)](https://github.com/M0okz/maccare/releases/tag/v0.2.19),
tag sur `c89d666c30680a2c23e4c061ea45b732ae3e4fd7`, [workflow réussi](https://github.com/M0okz/maccare/actions/runs/42644912784).
Ce statut remplace les mentions de développement non livré des notes datées
ci-dessous. Les validations et leurs limites sont conservées. La publication
ne remplace pas les copies installées. Voir [le bilan de livraison](release-integration-0.2.19.md).

DMG final : 16112155 octets, SHA-256 `6430fda069ac0f16455b2e9d9707762b3b8224670d73c7dbf3818cd7f1fc3a4e`.


## Publication 0.2.20 — 9 novembre 2026

[MacCare 0.2.20 (build 22)](https://github.com/M0okz/maccare/releases/tag/v0.2.20) est publié depuis `708e28b` après PR #28. Le workflow officiel, la vérification publique du DMG et du flux Sparkle, le site et la relecture Outline sont validés. [Preuves et limites](release-integration-0.2.20.md). Les copies installées restent préservées.

## Livraison 0.2.22 — 10 novembre 2026

L’installation depuis Applications est **publiée dans [MacCare 0.2.22 (build 24)](https://github.com/M0okz/maccare/releases/tag/v0.2.22)**, après fusion de la PR #30. Le tag `v0.2.22` vise `b73a43d45154c9adcf4087039cd90a2430e067c9`. Les CI de branche, PR et fusion ainsi que le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42716751129) réussissent. Ce statut remplace les mentions de développement non livré de ce correctif ; les preuves et limites datées restent conservées. La publication ne remplace pas les copies installées. Voir [la validation publique et les limites](release-integration-0.2.22.md).

## Livraison 0.2.23 — 10 novembre 2026

**Livré dans [MacCare 0.2.23 (build 25)](https://github.com/M0okz/maccare/releases/tag/v0.2.23)**, tag sur `a3c3f98f646fa27202607b47c6879969ca6eb72b` après fusion des PR #31 et #32. Le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42789605501) et les CI du code publié réussissent. Ce statut remplace les mentions de préparation/non livré de ces deux correctifs ; les validations historiques restent datées. Le rappel utilise une barre gérée seulement par SwiftUI ; l’analyse et le staging lisent les architectures sans lipo ni demande d’outils Xcode. [Vérifications publiques et limites](release-integration-0.2.23.md). La publication ne remplace pas les copies installées.
