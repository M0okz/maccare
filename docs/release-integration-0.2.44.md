# MacCare 0.2.44 — Retour d’Applications vers l’accueil

MacCare 0.2.44 (build 46) est disponible pour les Mac Apple Silicon sous macOS 13 ou ultérieur. La [PR 53](https://github.com/M0okz/maccare/pull/53) a intégré le correctif `3caa3f7`. Le tag `v0.2.44` désigne la fusion `774e076fe2aec75a213da3cd8cad29c1ff86c874`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.44).

Au retour d’Applications, la fenêtre affiche directement l’accueil avec les dernières mesures de batterie et la liste des processus déjà disponible. Lors du premier lancement, les lignes apparaissent dès le premier relevé. Les contrôleurs conservent les valeurs pendant la navigation et reprennent l’échantillonnage lorsque l’accueil redevient visible.

Lors des essais en DEV, deux retours avant correction montraient un fond presque vide puis un tableau sans lignes. Les premières lignes arrivaient 621 et 648 ms après l’activation d’Accueil. Sur quatre retours après correction, les lignes étaient présentes dès la première image lisible de l’accueil, entre 151 et 173 ms après activation, dans une fenêtre de 1 211 × 773 points. Le test `HomeReturnTests` parcourt les mêmes rubriques et vérifie que le processus témoin figure toujours dans la liste au retour.

Les CI de [branche](https://github.com/M0okz/maccare/actions/runs/45703803081), de [PR](https://github.com/M0okz/maccare/actions/runs/45703818691) et de [fusion](https://github.com/M0okz/maccare/actions/runs/45705759600) ont réussi, ainsi que la [publication](https://github.com/M0okz/maccare/actions/runs/45705773222).

Le [DMG public](https://github.com/M0okz/maccare/releases/download/v0.2.44/MacCare-0.2.44-arm64.dmg) fait 16824426 octets. Son SHA-256 `6adf9008b5248541a977575c45aa4e5f177b2f77ffd8f927a8ef33898d56551d` concorde avec la somme publiée, le manifeste et les métadonnées GitHub. Les contrôles Developer ID, Gatekeeper et de notarisation ont réussi sur le DMG et l’application montée en lecture seule. Le [flux Sparkle stable](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml) est identique au flux du tag. La même clé Ed25519 valide les flux de la 0.2.43 (build 45) et de la 0.2.44 (build 46), ainsi que le nouveau DMG. L’application embarque cette clé et l’adresse du flux stable.

Les dix pages HTML et le plan du site ont été vérifiés en HTTPS après déploiement. Le guide [Premiers pas](https://maccare.homeblack.fr/documentation/demarrer.html) décrit l’affichage des dernières mesures au retour d’Applications.
