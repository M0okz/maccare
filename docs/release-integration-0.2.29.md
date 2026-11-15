# MacCare 0.2.29 — protection M1 Max

**Publié le 15 novembre 2026 : [MacCare 0.2.29 (build 31)](https://github.com/M0okz/maccare/releases/tag/v0.2.29).**
Le tag vise `4ca502febbc86b4c4e735212b47706e3b873e4aa`, après fusion de la
[PR #38](https://github.com/M0okz/maccare/pull/38). Son arbre correspond exactement
au commit testé `bbd2fa4ea70439ebebb7065b72fabd0a164d7319`.
La version est proposée par le flux Sparkle habituel. Les corrections de stabilité
de la 0.2.28 sont conservées. Aucune installation utilisateur effectuée par ce chantier.

## Contenu

- Distinction entre priorité Apple de recharge complète et état illisible ;
  disparition du diagnostic infondé d'étalonnage en cours.
- Méthode avancée disponible en validation pour le seul `MacBookPro18,4`, avec
  CHIE et les garde-fous de journal/restauration, de température et de priorité Apple.
- Statut expérimental visible dans la protection et sa confirmation ; aucun
  ajout à la liste des modèles matériellement validés.
- Diagnostic CLI complet en lecture seule, 40 tentatives SMC dont quatre CHIE,
  télémétrie et compatibilité ; arguments inconnus refusés sans démarrer le service.
- Variante autonome de diagnostic conservée, sans démarrage de daemon.

La release fixe explicitement `MACCARE_M1_MAX_BATTERY_TRIAL=1` et
`MACCARE_PUBLIC_M1_MAX_TRIAL=1`. Le packaging vérifie le mode compilé du helper
et exige ce choix explicite pour la distribution. Le manifeste et Info.plist
consignent l'inclusion du mode M1 Max. Le nom distribué reste **MacCare**, avec
le flux Sparkle signé habituel ; ce n'est plus seulement une archive MacCare Dev.

## Limites

La lecture root distante de CHIE, la limite native et l'interface avancée ont été
observées sur MacBookPro18,4/macOS 27.2. Les essais matériels de maintien, reprise,
veille et restauration restent à réaliser. Une priorité Apple active ou illisible
continue de bloquer les écritures ; la nouvelle version ne garantit pas une
activation immédiate tant que ce signal persiste.

## Vérifications de livraison

CI de [PR](https://github.com/M0okz/maccare/actions/runs/43699294861) et de
[branche](https://github.com/M0okz/maccare/actions/runs/43699291803) réussies.
La suite Swift compte 657 tests exécutés réussis et 7 ignorés : 378 XCTest
dont 7 ignorés, puis 286 Swift Testing réussis. Les 21 tests Python de packaging,
les frontières C/Objective-C SMC et PowerUI sous ASan/UBSan et les trois variantes
CLI avec garde interposé de lecture seule passent. Le runner sans batterie est
accepté sans inventer de télémétrie. Le script de build reste compatible Bash 3.

La [chaîne officielle](https://github.com/M0okz/maccare/actions/runs/43700396432)
reconstruit, teste, signe et notarie le paquet avant publication.
DMG public : **16536469 octets**, SHA-256
`d7677bcb53adf05333c3ae899242de72874d6fe6456ee0465d39a75b6a6249e8`.
Après téléchargement : signatures Developer ID, tickets Apple app/DMG,
Gatekeeper, cinq exécutables arm64, version et canal de l'assistant vérifiés.
Les signatures Ed25519 du flux et du DMG sont vérifiées avec la clé publique
de la 0.2.28 ; le flux latest correspond exactement à la release 0.2.29 (31).
Le manifeste et Info.plist confirment le mode M1 Max en validation, avec
`MacCareDevelopmentBuild=false`. Le nouveau message est présent dans les deux
binaires app/helper et l'ancien message d'étalonnage en cours y est absent.

## Site, installation et documentation

Les dix pages HTML sont actualisées et relues en HTTPS, identiques aux sources ;
216 liens et ancres internes sont validés. Le conteneur reste sain. La couverture
horaire des HTML n'est pas confirmée ; leur état initial correspond aux sources
Git de la 0.2.28. La copie ciblée de retour arrière est supprimée après validation.
Les téléchargements, montages et scripts temporaires de vérification sont nettoyés.
Les preuves locales sont sous `build/release-0.2.29-qa/`.

La copie de production n'est ni lancée, ni remplacée, ni re-signée par cette
intervention. Gregory peut demander la mise à jour dans **À propos** et mettre
à jour l'assistant si MacCare le propose. La publication ne constitue pas la
validation physique du maintien/reprise/restauration sur M1 Max.

L'accès Outline prévu a été essayé et échoue avec `Bitwarden status failed` ;
les pages batterie, développement, publication et dépannage restent à synchroniser.
Voir la [note de synchronisation](outline-sync-pending-m1-max-battery.md).
