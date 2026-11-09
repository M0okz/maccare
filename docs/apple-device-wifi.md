# Gérer l'accès Wi-Fi des appareils Apple

## Point de reprise — 9 novembre 2026 à 14 h, Europe/Paris

Gregory a différé les essais matériels, puis demandé une reprise à 14 h.
L'automatisation ponctuelle `reprendre-les-tests-wi-fi-maccare` est créée dans
ce chat, pour une seule occurrence. **Ne pas déclarer la fonction fiable ou
livrée : la redécouverte après relance reste à valider.**

Le paquet Dev (20) montré à Gregory utilisait encore `AMDeviceSetValue` sur
`EnableWifiConnections`. Son clic a bien changé la valeur, et un premier relevé
réseau complet a suivi. Après une relance du paquet, le téléphone n'était plus
découvert, même avec une fenêtre de découverte portée temporairement à 2,5 s.
Cette sonde temporaire a été supprimée. L'enregistrement de ce Mac est une
**hypothèse de cause**, pas un diagnostic matériel confirmé.

La correction présente dans les sources utilise désormais
`AMDeviceGetWirelessBuddyFlags` et `AMDeviceSetWirelessBuddyFlags` : elle
initialise l'identité sans fil de ce Mac approuvé lors de l'activation, au lieu
de changer seulement une valeur globale sur l'iPhone. Les fixtures natives
et la compilation C passent ; **cette variante n'a pas été essayée sur l'iPhone
et doit être reconstruite dans le paquet avant tout nouveau clic**.

À 14 h : lire les consignes, rebrancher l'iPhone en USB avec Gregory, relever
les flags sans imprimer de données de jumelage, reconstruire le paquet Dev,
valider l'activation et sa relecture, débrancher, puis vérifier une lecture
réseau après une vraie relance. Ne pas refaire un jumelage, ne pas activer de
synchronisation de contenu, ne pas remplacer les apps installées. Les copies
quotidienne et Dev installée gardent leurs empreintes de référence. Le réglage
activé par Gregory est laissé en place ; aucun retour arrière silencieux.

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

## Vérifications

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
Le paquet montré est antérieur à la correction finale d'enregistrement de l'hôte.

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
