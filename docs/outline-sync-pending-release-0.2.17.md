# Outline et site — suivi de MacCare 0.2.17

9 novembre 2026. PR #24 fusionnée sur main, commit
`22d72fab270e55320a008188c02963fffa83a000`, tag `v0.2.17`.
Les CI de branche et PR sont réussies. La chaîne officielle de publication
[42630770167](https://github.com/M0okz/maccare/actions/runs/42630770167)
est réussie : release stable publiée le 9 novembre à 14:09:53 UTC, build 19.
Le DMG public est vérifié : signatures Developer ID et Ed25519, tickets Apple
app/DMG, Gatekeeper, cinq exécutables arm64 et helper cohérent. Le flux latest
correspond à la release. CI de main également réussie.
DMG : 16 049 174 octets ; SHA-256
`f787279babc1d33b67fc236fa2b726d1be153294cb014d2bd2c9438d6b7b332f`.

## Échec de l’accès interne

Les tentatives prescrites `homelab.py doctor`, `exec --service vikunja` et
`bw-exec --project` ne permettent pas d’atteindre les consommateurs des secrets :
code 2, `Homelab environment failed (file, format, command or timeout); no values displayed`.
Le diagnostic SSH sans secrets confirme le délai TCP sur
`bastion.int.homeblack.fr:2222`, y compris pour `cloud-docker-01` sans multiplexage.
Aucun accès API Outline/Vikunja n’est confirmé, aucun ticket Vikunja n’est créé.
Aucun secret n’est conservé dans cette note. Ne pas présenter cet état comme
un refus d’authentification Outline ou comme une synchronisation effectuée.

## Synchronisation à réaliser

Relire l’index Outline et les chapitres 02, 04, 06, 07, 08 et 11, puis intégrer
l’état livré de la 0.2.17 et ses preuves, sans remplacer le contenu sans rapport.
Conserver les validations datées des versions et prototypes précédents.
Rassembler les notes en attente Wi-Fi et batterie faible après vérification.

- Batteries iPhone/iPad et dernier niveau Watch, configuration Wi-Fi USB
  explicite via WirelessBuddyFlags, double lecture USB/réseau supprimée.
- Essais M1 : activation relue, réseau seul confirmé puis deux relances Dev
  réussies ; dernier niveau Watch sans date de mesure garantie. Longue veille,
  redémarrages matériels et autres versions système non validés.
- Alertes batterie faible facultatives : iPhone/iPad récents, option désactivée,
  seuil 20 % réglable, une alerte par épisode. Watch et accessoires exclus des
  alertes automatiques faute de date fiable. Aucun détecteur d’extinction.
- Catalogue hybride de mises à jour et sources officielles, sans garantie liée
  au nombre de fiches et sans extension implicite du périmètre de désinstallation.
- Sous-vues et feuilles standardisées, guides publics et limites réelles.
- Validation intégrée : Release arm64, signature stricte, 329 XCTest dont un
  test live facultatif ignoré, 247 Swift Testing et 19 tests de packaging,
  fixtures natives DeviceBatteryProbe/SMCWire/PowerUIBridge réussies.
- Dev intégrée : lecture Wi-Fi complète iPhone 86 % / Watch 74 % en 2,989 s ;
  les ronds réapparaissent après relance avec 84 % / 74 % à 14:57. Au premier
  affichage intégré, seuls les accessoires natifs étaient visibles ; aucun
  diagnostic de cause n’est établi. Ne pas promettre une disponibilité continue.
- Huit branches intégrées fermées, trois branches distantes supprimées ;
  worktrees et preuves préservés détachés. Nouveau chantier `codex/battery-cards`
  démarré en parallèle, modifications en cours préservées et hors tag 0.2.17.
- Copies installées non remplacées, aucun contrôle de charge ni installation
  de distribution effectué pendant cette livraison.

Le site utilise `cloud-docker-01:/opt/stacks/maccare/html`. Son redéploiement
reste impossible par le même bastion. La relecture HTTPS depuis ce Mac expire
également après 20 secondes : la version actuellement servie n’est pas confirmée.
Les sources de version préparées ne
constituent pas une preuve de publication HTTPS. Quand l’accès revient, vérifier
la sauvegarde récente et l’état distant, déployer les seuls fichiers concernés,
relire le HTML HTTPS et contrôler le conteneur ; retirer les copies de retour
arrière temporaires après validation.

Après écriture Outline, normaliser le texte, relire via documents.info avec
attente de visibilité si nécessaire et vérifier l’emplacement et les liens.
