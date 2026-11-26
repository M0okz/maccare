# MacCare 0.2.49 — Fenêtre de bilan de désinstallation lisible

[MacCare 0.2.49](https://github.com/M0okz/maccare/releases/tag/v0.2.49) (build 51) est disponible sur GitHub et via Sparkle pour Apple Silicon, à partir de macOS 13. Elle a été publiée le 26 novembre 2026 à 18:00 UTC. La [PR 59](https://github.com/M0okz/maccare/pull/59) réunit la correction `44d6656` et la préparation `d93620c`. Le tag annoté `v0.2.49` est posé sur le commit de fusion `850817c`.

Contenu : la fenêtre « <App> a été désinstallée » de la 0.2.48 héritait de l’apparence sombre de la fenêtre principale et était presque illisible. Elle applique désormais le style des feuilles des gestionnaires, avec des cartes et le bouton en pastille. Détails : [retrait des applications](application-removal.md).

**Contrôles.** Les [contrôles de branche](https://github.com/M0okz/maccare/actions/runs/45868401891), ceux de la [PR](https://github.com/M0okz/maccare/actions/runs/45868411932), le [contrôle de `main`](https://github.com/M0okz/maccare/actions/runs/45870575814) et la [publication](https://github.com/M0okz/maccare/actions/runs/45870582873) ont réussi. En local : 29 tests `Uninstall*`, dont un ignoré car il exige l’assistant signé, et le rendu de la feuille sous apparence sombre forcée.

**Distribution vérifiée après publication.** Le [DMG](https://github.com/M0okz/maccare/releases/download/v0.2.49/MacCare-0.2.49-arm64.dmg) fait 17174116 octets. Son SHA-256 `7251469ec1b0adbbfa0aa0868405d838f99b292391a33b7ce3eda11ac52e605c` concorde avec le fichier publié et `release.json`. L’app montée est acceptée par Gatekeeper (`Notarized Developer ID`), avec un ticket agrafé valide. Elle est en 0.2.49 (51), `MacCareDevelopmentBuild=false`, et son assistant reste au protocole 12. Le flux `appcast.xml` annonce 0.2.49, build 51.

**Limites.** La nouvelle fenêtre n’a pas encore été vue après une vraie désinstallation dans la version publiée. Le déploiement HTTPS du site et la synchronisation Outline restent en attente des accès Warpgate et Bitwarden.
