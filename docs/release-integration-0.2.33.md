# MacCare 0.2.33 — Densité de l’accueil

La version 0.2.33 (build 35) est publiée pour les Mac Apple Silicon sous macOS 13 ou ultérieur. Le tag `v0.2.33` vise `6b420fe00f2f109aece37874b18d12fc16f51927` et inclut le correctif approuvé `c795515`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.33) · [PR #42](https://github.com/M0okz/maccare/pull/42) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45186586394) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45188341713)

Le titre et les cartes de l’accueil s’adaptent à la largeur disponible dans la fenêtre. Sur le Mac de développement, dans une fenêtre de 1 149 × 845 points, le tableau est passé de 9 à 12 lignes complètes et la hauteur des cartes de 207 à 167 points. Le rendu de cette comparaison a été approuvé sur capture. [Mesures et conditions de vérification](display-layout.md).

## Distribution

- Les contrôles de branche, de PR et de fusion ont réussi. La chaîne du tag a construit et testé la distribution sur le commit de fusion.
- Le DMG téléchargé depuis GitHub contient 16507415 octets. Son SHA-256 `62d37dd19114f45b012d00686066156740d59d3b72732c8dae4ac4d2c041590d` correspond au manifeste et à la somme publiée.
- Les signatures Developer ID, les tickets de notarisation de l’app et du DMG, l’acceptation par Gatekeeper et l’architecture arm64 des cinq exécutables distribués ont été vérifiés.
- Le flux public Sparkle annonce la version 0.2.33 (build 35) et reprend les notes de version. Les signatures du flux et du DMG ont été vérifiées avec la clé publique qui valide également le flux de la 0.2.32. Le paquet public a été monté en lecture seule.

## Site

Les 10 pages publiques et le plan du site correspondent aux sources après vérification en HTTPS. Les destinations de 276 liens, ancres et références de ressources internes ont été contrôlées. [Site MacCare](https://maccare.homeblack.fr/) · [Guide de prise en main](https://maccare.homeblack.fr/documentation/demarrer.html)
