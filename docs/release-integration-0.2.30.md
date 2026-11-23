# MacCare 0.2.30 — état Apple et diagnostic de jauge

**Publié le 22 novembre 2026 : [MacCare 0.2.30 (build 32)](https://github.com/M0okz/maccare/releases/tag/v0.2.30).**
Le tag vise `2642316185abca80e1fe04640a7002117e7ff8e1`, après fusion de la
[PR #39](https://github.com/M0okz/maccare/pull/39). L’arbre correspond au commit
`9d0f1565f00b042ef3640c379a6d496754b1f004` testé avant fusion.

## Changements livrés

L’état de demande Apple est remonté avant activation, distinct de la disponibilité
de la méthode native. L’actualisation relit cet état sans activer la protection.
Une ancienne erreur Apple de préactivation peut être retirée après une lecture
explicitement favorable, sans masquer les autres erreurs ni une restauration.
Le diagnostic complet ajoute les dates du suivi de jauge via une lecture bornée,
sans numéro de série, en conservant les 40 lectures SMC dont CHIE.
[Détails et limites](m1-max-apple-charge-state.md).

MacBookPro18,4 reste en validation. La publication conserve les gardes de charge,
ne modifie pas le suivi Apple et ne garantit pas la levée d’une demande active.
Les essais matériels de maintien, reprise, veille et restauration restent à
réaliser sur le M1 Max. Aucun changement distant sur ce Mac pendant la livraison.

## Vérifications

- CI de [branche](https://github.com/M0okz/maccare/actions/runs/45015517962),
  de [PR](https://github.com/M0okz/maccare/actions/runs/45015523093) et de
  [fusion](https://github.com/M0okz/maccare/actions/runs/45016376606) réussies.
- 664 tests Swift réussis et 7 ignorés ; 21 tests Python de packaging ; frontières
  PowerUI/SMC sous sanitizers et trois variantes CLI avec garde de lecture seule.
- [Chaîne officielle](https://github.com/M0okz/maccare/actions/runs/45016404021)
  réussie : reconstruction, tests, Developer ID, notarisation app/DMG et Sparkle.
- DMG public téléchargé : **16581815 octets**, SHA-256
  `d5fc5110926e6c3791bdef38bb4944211467b3d475e2d09131c343deed5fb9d4`. Somme publiée et manifeste identiques.
- Signatures et tickets Apple de l’app et du DMG, Gatekeeper, cinq exécutables
  arm64, signatures Developer ID et équipe `5FAF9ZA2X9` vérifiés.
- Flux et DMG Ed25519 vérifiés avec la clé publique précédemment validée dans la
  0.2.28, également confirmée avec le flux signé 0.2.29 avant publication.
  Le flux latest correspond exactement à la 0.2.30 (32).
- Paquet distribué **MacCare**, `MacCareDevelopmentBuild=false`, mode M1 Max en
  validation présent. Descripteur de l’assistant : version 0.2.30, build 32,
  canal distribution. Les nouveaux champs de diagnostic et l’action
  d’actualisation sont présents dans les binaires.

La validation publique est statique : aucune installation ni ouverture de l’app
ou activation de protection. Le diagnostic exécutable a été testé dans le paquet
Dev préparatoire ; pas de nouvelle campagne graphique, VoiceOver ou matérielle
revendiquée. La copie de production est préservée.

## Site et documentation

Les dix pages HTML ont été déployées puis relues en HTTPS, identiques aux sources.
216 liens/ancres internes sont valides et le conteneur reste sain. Taille,
empreinte et liens de téléchargement correspondent au paquet vérifié.
La couverture des HTML par une sauvegarde horaire récente n’a pas pu être
confirmée : une copie temporaire ciblée a précédé les remplacements, puis a été
supprimée après validation. L’état précédent correspond aux sources Git.

Les téléchargements, montages et scripts temporaires sont nettoyés après les
contrôles ; les preuves JSON sont conservées sous `build/release-0.2.30-qa/`.
Outline reste non synchronisé : l’accès prescrit échoue avec `Bitwarden status
failed; check login, configured secret and server access`. La
[note de reprise](outline-sync-pending-m1-max-battery.md) conserve le statut livré.

## Nouveau diagnostic sur le M1 Max

Après la mise à jour depuis **À propos**, actualiser l’assistant si MacCare le
propose. Le diagnostic indépendant lit le nouveau helper inclus dans l’app :

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/MacCare.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:MACCARE_HELPER_VERSION' -c 'Print :EnvironmentVariables:MACCARE_HELPER_BUILD' /Applications/MacCare.app/Contents/Library/LaunchDaemons/org.maccare.helper.plist
sudo /Applications/MacCare.app/Contents/MacOS/MacCareHelper --battery-full-diagnostics
```

Ces commandes n’activent pas la protection et ne réinitialisent pas le suivi Apple.
La version du descripteur est celle du helper fourni, pas une preuve de la version
d’un éventuel processus launchd déjà chargé. Le JSON permet de comparer le signal
actuel (`compatibility.fullChargeOverride`) aux données enregistrées (`appleGauging`).
