# MacCare 0.2.39 — Jauge disque et survol des métriques

MacCare **0.2.39 (build 41)** est disponible pour les Mac Apple Silicon sous macOS 13 ou ultérieur. Le tag `v0.2.39` pointe sur `c484dd79b0f886444377040ab7bad6d68c207dd6`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.39) · [PR 48](https://github.com/M0okz/maccare/pull/48) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45367322433) · [Publication](https://github.com/M0okz/maccare/actions/runs/45367331587).

La jauge disque passe de 5 à 7 points et change de couleur selon le pourcentage utilisé affiché. Le bleu couvre 0 à 69 %, l’orange 70 à 89 % et le rouge 90 à 100 %. La courbe GPU et la jauge disque utilisent le même effet de survol que le CPU, la mémoire et le réseau.

Les quatre tests ciblés de stockage sont passés lors de la validation DEV. Des captures de la fenêtre native ont confirmé les 7 points de la jauge rouge à 97 % d’occupation et le survol des cinq tuiles. Les deux CI de préparation, la CI de fusion et la chaîne de publication ont réussi.

Le [DMG public](https://github.com/M0okz/maccare/releases/download/v0.2.39/MacCare-0.2.39-arm64.dmg) contient 16772505 octets. Sa somme SHA-256, `b0f754c02bffea3d43760c947de4af4daa0cc761a45375cea5851c004d823421`, correspond à GitHub, au manifeste et au fichier de contrôle. Le DMG et l’application embarquée ont passé les contrôles de signature, de ticket de notarisation et de Gatekeeper. Les signatures Ed25519 du [flux stable](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml) et du DMG ont été vérifiées avec la clé publique qui valide le flux de la 0.2.38.

Les dix pages du [site public](https://maccare.homeblack.fr/) et son plan correspondent aux sources après déploiement. Les guides [Premiers pas](https://maccare.homeblack.fr/documentation/demarrer.html) et [Performances](https://maccare.homeblack.fr/documentation/performances.html) décrivent les seuils et le survol.
