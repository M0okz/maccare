# Gérer l'accès Wi-Fi des appareils Apple

## Reprise matérielle — 9 novembre 2026 après 14 h, Europe/Paris

Gregory a rebranché et déverrouillé l’iPhone sur le MacBook Pro M1. Le paquet
MacCare Dev **0.2.16 (21)** a été reconstruit dans
`build/apple-device-wifi-resume/MacCare.app`, puis lancé depuis ce chemin.
L’automatisation ponctuelle de reprise a été consommée et supprimée.
**Le test sans câble après relance reste en attente du débranchement.**

Cette reprise valide pour la première fois sur l’iPhone l’appel
`AMDeviceSetWirelessBuddyFlags` de la correction. La lecture USB initiale donnait
les flags `0x2` : accès Wi-Fi actif. L’activation explicite autorisée a envoyé
les flags incluant `0x1 | 0x2`, puis confirmé l’état Wi-Fi actif par relecture
(réponse complète, **1,981 s / 0,1686 s CPU**). Le bit d’initialisation est une
commande de l’interface ; sa seule absence dans la lecture initiale ne prouve
pas la cause de la redécouverte irrégulière du premier prototype.

La lecture batterie détectait le même iPhone sur USB et réseau et interrogeait
deux fois le téléphone et sa Watch. La sonde privilégie maintenant USB et saute
le second transport seulement après une lecture batterie réussie. Si USB échoue,
le réseau reste un repli possible. Sur matériel : **iPhone 81 %, Watch 75 %**,
une seule ligne par appareil, **1,283 s / 0,1052 s CPU**, contre
**3,455 s / 0,2227 s CPU** avant dédoublonnage. Ces mesures concernent un appel
ponctuel du processus, pas l’énergie totale du système.

Le paquet Dev affiche l’iPhone et la Watch dans la carte Batterie de l’Accueil,
et « Accès Wi-Fi activé » avec le bouton « Désactiver l’accès Wi-Fi » dans
Batterie → Réglages → Appareils Apple. Aucun clic de désactivation n’a été fait.
Les copies `/Applications/MacCare.app` et `/Applications/MacCare Dev.app` sont
préservées. La synchronisation Outline reste à reprendre après échec du helper
Homelab : voir [la note de synchronisation](outline-sync-pending-apple-device-wifi.md).

Le premier paquet Dev (20) montré à Gregory utilisait encore `AMDeviceSetValue`
sur `EnableWifiConnections`. Un relevé sans câble avait fonctionné, puis la
redécouverte après relance avait échoué, y compris avec une fenêtre temporaire
à 2,5 s. Ce résultat ancien reste distinct du test de la nouvelle correction.

Développement du 9 novembre 2026, **non livré**. Branche
`codex/apple-device-wifi`, issue de `6b207f1`, dans le worktree
`build/worktrees/apple-device-wifi` du dépôt produit. Les deux commits de lecture
des batteries (`d2c5c8b`, `6b207f1`) restent inclus. Les changements Applications
simultanés du checkout principal ne sont pas copiés dans ce worktree.

## Parcours

Dans **Batterie → Réglages**, la carte **Appareils Apple** lit les appareils déjà
approuvés et leur état Wi-Fi. Un bouton propose **Activer l'accès Wi-Fi** ou
**Désactiver l'accès Wi-Fi** selon cet état. Il est nécessaire de brancher le
câble USB et de déverrouiller l'appareil pour modifier le réglage. Le premier
« Faire confiance » reste une action sur l'iPhone/iPad et le Mac.

La carte reprend le style existant de Batterie, avec titre, nom d'appareil,
état textuel et bouton natif. Elle conserve les états de lecture, absence,
réglage inconnu, refus, confirmation et connexion sans USB. Le texte explique
la relation avec l'option Finder **Afficher cet iPhone lorsqu'il est en Wi-Fi**.
Une action Actualiser relit l'état ; l'ouverture ne change aucun réglage.
Après débranchement, la modification reste désactivée avec une consigne USB.

## Frontière entre lecture et configuration

Le mode par défaut de `MacCareDeviceBatteryProbe` reste une lecture des
batteries. `--list-wifi` ne fait que lire. Seul le mode explicite
`--set-wifi <identifiant haché> on|off` peut écrire :

- arguments stricts, cible exacte, USB, jumelage existant et session validée ;
- seul le réglage de connexion sans fil est modifié, par
  `AMDeviceSetWirelessBuddyFlags` ; activation des bits identité `0x1` et Wi-Fi
  `0x2`, autres flags préservés ; désactivation du seul bit `0x2` ;
- relecture du même réglage : un statut API réussi sans valeur conforme ne
  suffit pas pour annoncer la réussite ;
- aucun jumelage automatique, installation, autre réglage de synchronisation,
  remplacement du helper privilégié, compte iCloud ou application compagnon.

L'état est demandé à `AMDeviceGetWirelessBuddyFlags` (bit Wi-Fi `0x2`), uniquement
si cet appel existe et réussit avec des flags valides. Un échec reste inconnu.
Le premier prototype lisait la clé `EnableWifiConnections`, absente avant
activation sur l'iPhone iOS 27.2 testé. La nouvelle variante traite également
l'identité sans fil de l'hôte, conformément à l'interface MobileDevice.

Sources primaires : [outil wificonnection de l'auteur d'AirBattery](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/libimobiledevice/bin/wificonnection.c),
[usage et constantes MobileDevice](https://github.com/mountainstorm/MobileDevice/blob/master/amdevice.py).
L'implémentation est native et indépendante ; aucun de leurs binaires n'est embarqué.

## Énergie et délais

La carte de configuration effectue une lecture à l'ouverture et après action,
sans nouvelle boucle de sondage. Le suivi des batteries conserve son cache
partagé et sa fréquence d'une minute, deux en économie d'énergie, cinq après
absence/échec, et aucun scan Bluetooth permanent.

La lecture réseau réelle ayant pris 3,931 s, le plafond initial de quatre
secondes était trop proche. Il passe à **six secondes dans la sonde et sept
dans le parent**, sans augmenter la fréquence des lectures. Les appels sont
effectués hors de l'interface et de l'exécuteur coopératif. Une acquisition déjà
lancée reste bornée même si la vue ferme.

## Vérifications de la reprise

- Build Release arm64, helper natif et paquet Dev **0.2.16 (21)** signés
  Apple Development ; aucune copie installée remplacée.
- Nouvelle fixture native : découverte réseau avant USB du même identifiant,
  un seul accès avec préférence USB. La fixture échouait avant correction,
  puis passe sous ASan/UBSan ; un second cas valide le repli réseau après échec USB.
- Preuves locales dans `build/apple-device-wifi-qa/` :
  `resume-usb-configuration.json`, `resume-usb-batteries.json`,
  `resume-usb-deduplicated.json`, `duplicate-discovery-red.log`,
  `duplicate-discovery-green.log`, `resume-package.log`.

## Vérifications antérieures — premier prototype

- Build Release arm64 et paquet MacCare Dev **0.2.16 (20)** signés Apple
  Development, sans flux Sparkle. Paquet propre au worktree :
  `build/apple-device-wifi/MacCare.app`. Aucune copie installée remplacée.
- **28 tests Swift ciblés** : lecture batterie, cache, concurrence, délai,
  configuration explicite d'une seule cible, refus sans USB ou appareil listé,
  résultat non confirmé si la relecture diffère, fusion USB/réseau.
- Fixtures natives sous ASan/UBSan : aucun setter en lecture normale, refus
  sans confiance/USB/cible exacte, flags sans rapport préservés, identité
  initialisée à l'activation et état inconnu sur erreur du getter.
- Carte et bouton vérifiés dans l'arbre natif et une capture de l'écran réel.
  Gregory a cliqué **Activer** dans le premier prototype ; MacCare a relu **Accès Wi-Fi activé**, montré
  le bouton **Désactiver** et le message de confirmation. Ce test n'est pas
  une activation silencieuse par le lecteur.
- Gregory a débranché le câble. La sonde a vérifié `usbConnected: false`,
  `wifiEnabled: true`, `canConfigure: false` ; lecture de connexion complète
  en **2,747 s / 0,1438 s CPU**.
- Lecture batterie sans câble : **iPhone 93 %, Watch 84 %**, réponse complète
  en **3,931 s / 0,1725 s CPU** du processus, sans erreur.

Le test de délai Swift final passe en environ 7,1 s ; les 28 tests ciblés passent.
Le paquet (20) montré lors de ces essais antérieurs précède la correction WirelessBuddyFlags ; le paquet (21) de la reprise est décrit plus haut.

Ces chiffres ne mesurent pas l'énergie des démons système ou l'autonomie du
téléphone/de la Watch sur la durée. L'âge du registre Watch, l'accès après une
longue veille, les autres versions iOS/macOS et un parcours VoiceOver/clavier
complet ne sont pas validés. Le niveau Watch reste le dernier connu par
l'iPhone. La désactivation réelle n'est pas testée à ce stade ; ses barrières
et sa relecture sont simulées, et le réglage activé par Gregory est conservé.

Composants : `MobileDeviceWiFiView`, `MobileDeviceWiFiModel`,
`MobileDeviceBatteryReader.execute`, modes du lecteur natif et tests associés.
L'option de connexion Wi-Fi est persistante sur l'appareil ; les relevés
MacCare restent en mémoire uniquement.
