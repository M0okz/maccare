# MacCare 0.2.40 — Tableau des processus et carte Mémoire

MacCare **0.2.40 (build 42)** est disponible sur GitHub et via Sparkle pour les Mac Apple Silicon sous macOS 13 ou ultérieur. La PR 49 a intégré les cinq commits du tableau ainsi que `4dd14c8` et `8ea716c` pour la carte Mémoire. Le tag `v0.2.40` pointe sur `f4800aa14103141a677a5871d5e5898d7730a4e7`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.40) · [PR 49](https://github.com/M0okz/maccare/pull/49).

Le tableau classe WindowServer par empreinte mémoire et affiche un PID représentatif pour chaque groupe. La fiche s’ouvre en fondu sur le membre désigné. Le score énergétique combine la charge CPU et les réveils du processeur. La colonne affiche la note seule et son infobulle précise l’échelle de 0 à 20. La carte Mémoire affiche la RAM sur la dernière minute, avec une échelle verticale ajustée aux relevés, ainsi que le swap utilisé.

Les CI de branche, de PR et de fusion ont réussi. Le flux stable a été téléchargé après publication. Son numéro interne est supérieur à celui de la version 0.2.39 (41). Le flux et le DMG ont passé la vérification Ed25519 avec la clé qui valide le flux précédent. [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45384136781) · [Distribution](https://github.com/M0okz/maccare/actions/runs/45384168758) · [Flux Sparkle](https://github.com/M0okz/maccare/releases/latest/download/appcast.xml).

Le DMG public contient 16814740 octets. Son empreinte SHA-256, `f8de6b356676c5c42210c3ed608bc3e12857ae5371eb53ec8de367df485f4bb5`, correspond au manifeste, au fichier de contrôle et à l’empreinte de l’artefact GitHub. Le DMG et l’application embarquée ont passé les contrôles de signature, de notarisation et de Gatekeeper. [Télécharger le DMG](https://github.com/M0okz/maccare/releases/download/v0.2.40/MacCare-0.2.40-arm64.dmg).

Après déploiement, les dix pages et le plan du site public correspondent aux sources. Les guides décrivent les mesures mémoire, les PID et le score énergétique. [Premiers pas](https://maccare.homeblack.fr/documentation/demarrer.html) · [Performances](https://maccare.homeblack.fr/documentation/performances.html).
