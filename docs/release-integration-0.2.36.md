# MacCare 0.2.36 — Défilement de la liste des processus

MacCare 0.2.36 (build 38) est disponible pour Apple Silicon à partir de macOS 13. Dans l’accueil, les titres des colonnes restent lisibles pendant le défilement et l’actualisation de la liste. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.36).

## Vérifications

Le tag `v0.2.36` pointe sur `f8db244bbfe264824f6cc275d85dc3834215fea2`, qui intègre le correctif `2c6f14c`. Les tests incluent la comparaison du rendu AppKit en modes clair et sombre. [PR 45](https://github.com/M0okz/maccare/pull/45) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45300741012) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45300747470).

Dans MacCare DEV sous macOS 27.0.1, la bande des titres a conservé le même rendu aux index 0, 70, 263 et 4, y compris pendant l’actualisation des valeurs. La vérification interactive a été réalisée en mode sombre sur ce Mac.

Le DMG public contient 16677381 octets. Son SHA-256, `3cdeaa9b05447ed6ad6d1cc0c2980b49cc96d099131bec9898ea428d80dd0dc8`, correspond à la somme et au manifeste publiés. Gatekeeper a accepté le DMG et l’application montée en lecture seule. Leurs tickets de notarisation ont été validés. Les signatures Ed25519 du flux stable et du DMG ont été vérifiées avec la clé publique qui valide la version précédente. [DMG officiel](https://github.com/M0okz/maccare/releases/download/v0.2.36/MacCare-0.2.36-arm64.dmg) · [Flux Sparkle](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml).

Les dix pages du site et son plan ont été relus en HTTPS après publication. Le guide de prise en main décrit le comportement de l’en-tête fixe. [Site public](https://maccare.homeblack.fr/) · [Guide de prise en main](https://maccare.homeblack.fr/documentation/demarrer.html).
