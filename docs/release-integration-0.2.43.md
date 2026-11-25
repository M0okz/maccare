# MacCare 0.2.43 — Boutons de fenêtre macOS

MacCare 0.2.43 (build 45) est disponible pour les Mac Apple Silicon à partir de macOS 13. Le tag `v0.2.43` désigne la fusion `fd5c746bbec9f4e123685ff571d79121ee88ee4d`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.43) · [PR 52](https://github.com/M0okz/maccare/pull/52).

La fenêtre principale applique son habillage après le rattachement du contenu SwiftUI. Fermer, réduire et agrandir restent accessibles au lancement, après un changement de rubrique et après la restauration d’une fenêtre réduite. Le correctif et son test de régression figurent dans le commit `5dfb17c`.

La DEV a vérifié les trois cibles natives à onze étapes. Une sonde indépendante a vérifié quatre lancements, 640 transitions de disponibilité des mises à jour et quatre restaurations. Les contrôles portaient sur la vue qui reçoit le clic au centre de chaque bouton, dans une session verrouillée. [Détails des essais](sidebar-spacing.md).

Les CI de [branche](https://github.com/M0okz/maccare/actions/runs/45574230650), de [PR](https://github.com/M0okz/maccare/actions/runs/45574242722) et de [fusion](https://github.com/M0okz/maccare/actions/runs/45576047065) ont réussi, ainsi que la [publication](https://github.com/M0okz/maccare/actions/runs/45576054214).

Le [DMG](https://github.com/M0okz/maccare/releases/download/v0.2.43/MacCare-0.2.43-arm64.dmg) fait 16821161 octets. Son SHA-256 `f1042b243ee8298955691b06170aae0665f35c45e22ae069aae8b5646bb248ae` correspond à la somme publiée, au manifeste et aux métadonnées GitHub. Les signatures Developer ID, Gatekeeper et la notarisation ont été contrôlés sur le téléchargement public et l’application montée en lecture seule. Le [flux Sparkle stable](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml) est identique à celui du tag. La même clé publique a validé les flux des builds 44 et 45 et la signature du nouveau DMG. L’application embarque cette clé et l’adresse stable du flux.

Les dix pages HTML et le plan du site ont été vérifiés en HTTPS après déploiement. Le guide [Premiers pas](https://maccare.homeblack.fr/documentation/demarrer.html) indique où se trouvent les commandes natives.
