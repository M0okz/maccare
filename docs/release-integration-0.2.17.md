# Intégration MacCare 0.2.17

Préparation du 9 novembre 2026, **non publiée à ce stade**, branche
`codex/release-0.2.17`. Gregory demande de réunir tous les commits produit,
fusionner main et fermer les branches pour une nouvelle release.

## Branches réunies

- `codex/apple-device-batteries` et `codex/standardized-subviews`, tête `40a61d1` :
  lecteur mobile, catalogue hybride d’applications, guides publics, sous-vues.
- `codex/apple-device-wifi`, tête `c3d9317` : configuration Wi-Fi explicite,
  dédoublonnage USB/réseau, validation réelle après deux relances sans câble.
- `codex/device-battery-alerts`, tête `d64c5aa` : option désactivée par défaut,
  seuil réglable, alertes iPhone/iPad frais, Watch exclue des alertes automatiques.
- `codex/bundled-mas` et `codex/native-file-disk-tools` : code déjà livré dans
  0.2.12. `git range-diff c424edc^..c424edc cf62181^..cf62181` confirme le même
  patch de code, avec un contexte documentaire différent et la mention du
  cherry-pick. La fusion historique `88cd083` conserve l’arbre produit actuel
  tout en rattachant ces commits pour permettre une fermeture sans perte.
- `claude/site-0.2.9` est déjà ancêtre de main ; aucun ancien contenu du site
  n’est réintroduit.

Les deux conflits de `docs/development-builds.md` conservent les deux historiques.
Aucun conflit fonctionnel. Les worktrees de QA sont conservés, détachés après
fusion avant suppression des branches ; leurs paquets et preuves restent présents.

## Validation de l’ensemble

Release arm64 et signature stricte du paquet Dev 0.2.17 (22) réussies.
329 XCTest, dont un test réseau live facultatif ignoré, sans échec ;
247 Swift Testing et 19 tests Python de packaging passent. Fixtures natives
DeviceBatteryProbe, SMCWire et PowerUIBridge réussies sous leurs contrôles.

Le lecteur signé du paquet intégré retourne sans câble iPhone 86 % et Watch
74 %, réponse complète en 2,989 s. L’interface Appareils Apple relit Wi-Fi actif,
modification désactivée sans USB. Réglages → Menu affiche l’alerte appareil
désactivée et son seuil à 20 %. Aucun réglage personnel n’est changé par la QA.
Les validations visuelles détaillées des autres composants restent celles de
leurs branches ; une campagne complète VoiceOver/clavier n’est pas revendiquée.

Preuves : `build/release-0.2.17-qa/`. Les copies installées de MacCare et MacCare
Dev ne sont ni remplacées ni re-signées. Le défaut du matin ne s’est pas reproduit
pendant les deux relances Wi-Fi, mais longue veille et redémarrages restent
non testés. L’énergie des démons et des appareils sur la durée n’est pas mesurée.

## Documentation et accès de livraison

Notes utilisateur : [0.2.17](release-notes/0.2.17.md). Outline et le suivi Vikunja
restent en attente : le helper Homelab échoue avec son erreur masquée ; le
bastion TCP 2222 est injoignable, y compris pour `cloud-docker-01`. Aucun jeton
n’a été affiché, aucune authentification API Outline/Vikunja n’est confirmée.
La publication GitHub utilise l’accès GitHub existant et reste indépendante.
Le redéploiement du site exige le rétablissement de cet accès ; conserver la
version réellement en ligne distincte des sources préparées.
