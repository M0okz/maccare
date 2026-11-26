# MacCare 0.2.46 — Historique local de l’activité

La [version 0.2.46](https://github.com/M0okz/maccare/releases/tag/v0.2.46) (build 48) est disponible sur GitHub et via Sparkle pour les Mac Apple Silicon sous macOS 13 ou ultérieur. La [PR 55](https://github.com/M0okz/maccare/pull/55) intègre l’historique `dbbbf6a` et les corrections `5ec7a6d`. Le tag `v0.2.46` désigne la fusion `2bc93641f7bda44585767a45f35668fb279bf17f`.

Les courbes CPU, GPU, mémoire et réseau retrouvent les relevés au lancement. L’archive garde la dernière heure par tranches de cinq secondes et jusqu’à trente jours par minute. Chaque métrique suit ses propres interruptions. Les détails affichent la moyenne sur le temps observé et l’heure locale du pic. [Fonctionnement de la collecte et du stockage](activity-metrics-cache.md).

Sur la DEV signée, le pic injecté à 100 % deux jours avant l’essai a conservé sa date et son heure après fermeture et relance. La suite locale a compté 728 tests réussis et sept ignorés. Sur une archive synthétique de 216 000 lignes minute, la lecture et le rendu d’une courbe CPU sur trente jours prennent 12,4 ms en médiane après optimisation, contre 21,1 ms pour le même format avant optimisation. La mesure couvre une seule machine et 90 actualisations par variante.

La [CI de branche](https://github.com/M0okz/maccare/actions/runs/45809342622), la [CI de PR](https://github.com/M0okz/maccare/actions/runs/45809411533), la [CI de la fusion](https://github.com/M0okz/maccare/actions/runs/45811304319) et la [distribution officielle](https://github.com/M0okz/maccare/actions/runs/45811313159) ont réussi.

Le [DMG public](https://github.com/M0okz/maccare/releases/download/v0.2.46/MacCare-0.2.46-arm64.dmg) fait 16882643 octets. Son empreinte SHA-256 `70785871bb6fffc3f8d2ae9148e6888e137f2b83cb4e29da0714939f6b3c2b31` correspond à la somme publiée, au manifeste et aux métadonnées GitHub. Le DMG téléchargé et son application montée en lecture seule ont passé les contrôles de signature, de notarisation et de Gatekeeper. La clé publique embarquée valide l’ancien flux 0.2.45, le nouveau flux et la signature du DMG. Le [flux Sparkle stable](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml) correspond au flux du tag et contient les notes de cette version.

Les dix pages HTML publiques et le plan du site ont été relus en HTTPS et correspondent aux sources. Le [guide des performances](https://maccare.homeblack.fr/documentation/performances.html#activite) explique comment lire l’historique et interpréter les coupures.
