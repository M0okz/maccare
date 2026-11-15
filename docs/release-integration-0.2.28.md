# MacCare 0.2.28 — stabilité et empreinte système, 15 novembre 2026

**Publié et installé sur le Mac de Gregory.** [MacCare 0.2.28 (build 30)](https://github.com/M0okz/maccare/releases/tag/v0.2.28)
est issu du tag `v0.2.28`, commit `3399a6ecbcbc346aa95d78ac2311f8c4cc3531be`,
après fusion de la [PR #37](https://github.com/M0okz/maccare/pull/37).

## Corrections livrées

- Cache de l'historique batterie réutilisé quand le fichier est inchangé ; détection
  des écritures d'une autre instance et réapplication de la fenêtre temporelle.
- Lecture simultanée de stdout et stderr pour éviter le blocage d'une commande
  remplissant sa sortie d'erreur, en conservant sorties et code de retour.
- Minuteur dédié pour le délai maximal des diagnostics disque, séparé de la file
  globale utilisée par les lectures bloquantes. Aucun relâchement du test de délai.

Cadences, limites d'historique, verrou interprocessus, signatures et politique
de charge sont conservés. [Mesures, parcours et limites](stability-performance.md).
Le gain d'environ 91 % concerne le test de traitement de l'historique, pas une
promesse de baisse équivalente du CPU total ou de consommation électrique.

## Vérifications

La suite locale finale compte 649 tests Swift exécutés réussis, dont les deux
intégrations réseau sur fixtures. Le moteur inchangé a passé 99 tests Rust,
dont la frontière de volume monté ; 19 tests Python de packaging réussissent.
Les deux premières CI ont révélé un dépassement du délai disque : aucune erreur
après 2,177 / 2,310 s pour un timeout de 0,05 s. La file dédiée corrige le cas
sur les deux CI complètes, sans changer l'erreur attendue ni la borne de 1,5 s.
Le test termine en 0,374 s dans la CI de PR finale. Le retard de la file globale
est l'hypothèse principale ; les traces initiales n'isolent pas entièrement
le lancement du processus de l'ordonnancement du callback.

CI de [branche](https://github.com/M0okz/maccare/actions/runs/43692145908) et de
[PR](https://github.com/M0okz/maccare/actions/runs/43692148240) réussies ; l'arbre
fusionné correspond exactement à celui testé. La [chaîne officielle](https://github.com/M0okz/maccare/actions/runs/43692935593)
reconstruit, teste, signe et notarie les artefacts avant publication.

DMG public : **16481787 octets**, SHA-256
`5ac0bee09407a74f8447ab93a7227040486d1ee010d02a349c7bf49f68decdeb`. Après téléchargement : empreintes du DMG/manifest/GitHub cohérentes,
signatures Developer ID, tickets Apple app/DMG, Gatekeeper, cinq exécutables arm64,
version et canal du helper vérifiés. Signatures Ed25519 du flux et du DMG validées
avec la clé publique de l'installation précédente ; latest correspond à 0.2.28.

## Installation et documentation

La copie quotidienne `/Applications/MacCare.app` passe de **0.2.26 (28)** à
**0.2.28 (30)** par **Sparkle**. Son binaire correspond au paquet public.
Le redémarrage et l'interface de la version installée sont vérifiés ; les cinq
préférences repères restent identiques. Aucun nouvel accès système ou réglage
de charge n'est accordé pendant la mise à jour.

Les dix pages HTML du site public correspondent aux sources actualisées en HTTPS,
avec les liens de téléchargement, taille et empreinte de la nouvelle release.
Le conteneur reste sain, les droits sont conservés. La couverture horaire des
HTML n'est pas confirmée ; les fichiers avant déploiement correspondaient aux
sources Git et la copie ciblée de retour arrière est supprimée après vérification.
Les pages Outline concernées sont actualisées et relues, sans effacer les
validations antérieures. Suivi : [Homelab #130](https://todo.homeblack.fr/tasks/7182).

Les téléchargements, montages et scripts temporaires sont nettoyés. Preuves
locales : `build/release-0.2.28-qa/` et `build/stability-2026-11-15/`.
Les limites de QA précédentes restent explicites : accès complet au disque absent,
pas de veille prolongée, cycle matériel de charge, VoiceOver exhaustif ou autre
modèle/version de macOS nouvellement validé pendant cette livraison.
