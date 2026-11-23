# MacCare 0.2.31 — accueil et processus

Publié le 23 novembre 2026 pour les Mac Apple Silicon avec macOS 13 ou ultérieur.
Le tag `v0.2.31` vise `08aaf8a907e4b54aad81aa1a7e95c5e7b7904e7d`. Le paquet public porte le numéro de build 33.
[Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.31) · [Intégration](https://github.com/M0okz/maccare/pull/40) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45086775060)

L’accueil présente les mesures, le tableau des processus et les commandes de ventilation
sur les Mac pris en charge. Le volet latéral s’ouvre au survol et les autorisations
manquantes sont regroupées dans une bulle. Les correctifs batterie M1 Max de la 0.2.30
sont inclus. Les limites matérielles de cette validation restent celles des
[notes de compatibilité](m1-max-apple-charge-state.md).

## Vérifications

- Tests Swift locaux de la branche intégrée : 682 réussis, 7 ignorés. Les scénarios de ventilation ont été exercés par simulation.
- Contrôles GitHub de branche, de pull request et de fusion réussis avant la création du tag.
- DMG public de 16660980 octets, SHA-256 `2b0625f633449ecca9513224768b617383761a8c2a8e500519d1b9fbd133a736`. La somme publiée et le manifeste correspondent à l’archive téléchargée.
- Signatures Developer ID et tickets de notarisation de l’app et du DMG vérifiés. Gatekeeper a accepté l’app, et les cinq exécutables distribués sont arm64.
- Les signatures du DMG et du flux Sparkle ont été vérifiées avec la clé publique déjà installée. Le canal de mise à jour public fournit le flux signé de la 0.2.31.
- Le site et ses neuf pages de documentation ont été relus en HTTPS après déploiement. Toutes correspondent aux sources publiées.

La vérification du paquet de distribution a été faite en lecture seule. Les essais de l’interface et du redimensionnement ont été effectués dans MacCare Dev.
