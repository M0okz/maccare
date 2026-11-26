# MacCare 0.2.48 — Désinstallation des apps App Store et confirmation par Touch ID

[MacCare 0.2.48](https://github.com/M0okz/maccare/releases/tag/v0.2.48) (build 50) est disponible sur GitHub et via Sparkle pour Apple Silicon, à partir de macOS 13. Elle a été publiée le 26 novembre 2026 à 15:53 UTC. La [PR 58](https://github.com/M0okz/maccare/pull/58) réunit la correction `d15c7af` et la préparation `c9922de`. Le tag annoté `v0.2.48` est posé sur le commit de fusion `dd36d47`.

Contenu : les conteneurs sont retirés avec les droits de la session, et seuls les éléments d’un autre compte passent par l’administrateur. Un refus de confidentialité de macOS est expliqué, une fenêtre confirme la désinstallation et l’inventaire ajoute les caches WebKit et les préférences ByHost. Le protocole 12 de l’assistant permet la confirmation par Touch ID. Détails et limites : [retrait des applications](application-removal.md).

**Contrôles.** Les [contrôles de branche](https://github.com/M0okz/maccare/actions/runs/45849327995), ceux de la [PR](https://github.com/M0okz/maccare/actions/runs/45849337646), le [contrôle de `main`](https://github.com/M0okz/maccare/actions/runs/45851461302) et la [publication](https://github.com/M0okz/maccare/actions/runs/45851469058) ont réussi. En local : 457 XCTest dont 8 ignorés et 295 tests Swift Testing, sans échec.

**Distribution vérifiée après publication.** Le [DMG](https://github.com/M0okz/maccare/releases/download/v0.2.48/MacCare-0.2.48-arm64.dmg) fait 17158480 octets. Son SHA-256 `09f233d9fa90e4ed41ab4dbd2697a0eb22c1a1b79e71b5a46ec3d9236d961f58` concorde avec le fichier publié et `release.json`. L’app montée est acceptée par Gatekeeper (`Notarized Developer ID`), avec un ticket agrafé valide. Elle est en 0.2.48 (50), `MacCareDevelopmentBuild=false`, et son assistant contient l’opération de désinstallation. Le flux `appcast.xml` du dernier lien annonce 0.2.48, build 50.

**Après installation.** Sur chaque Mac, il faut utiliser **Batterie → Mettre à jour l’assistant** pour passer l’assistant en protocole 12. Sinon, la désinstallation conserve le dialogue administrateur.

**Limites.** Le parcours Touch ID n’a pas encore été observé à l’écran. La désinstallation réelle de Reeder a été validée avec MacCare Dev (Apple Development), avant la publication, sur le Mac de développement. Le second MacBook n’a pas été rejoué. La page du site et les guides sont à jour dans le dépôt ; leur déploiement HTTPS et la synchronisation Outline restent à faire, faute d’accès Homelab et Bitwarden au moment de la livraison.
