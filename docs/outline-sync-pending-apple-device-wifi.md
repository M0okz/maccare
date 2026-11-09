# Synchronisation Outline en attente — appareils Wi-Fi

9 novembre 2026. État source : correction WirelessBuddyFlags et dédoublonnage USB/réseau, branche `codex/apple-device-wifi`.
Le [point de reprise](apple-device-wifi.md) est la référence locale actuelle.

La synchronisation du dernier état n'est **pas confirmée**. L'accès prescrit
a été essayé avec `homelab.py bw-exec --project` sur ce worktree, puis vérifié
avec `doctor --service bitwarden`. Les deux commandes terminent avec le code 2 :

```text
Homelab environment failed (file, format, command or timeout); no values displayed
```

Aucune valeur secrète n'est enregistrée ici. Ce résultat ne prouve ni un refus
d'authentification Outline ni une panne de son API : l'échec concerne le chemin
d'accès Homelab avant confirmation documentaire.

À la reprise du 9 novembre après 14 h, `doctor --service bitwarden` échoue
encore avec le code 2. Un diagnostic SSH sans commande de secrets confirme
`connect to host bastion.int.homeblack.fr port 2222: Operation timed out`, même
sans multiplexage. Aucune API Outline n’a donc été authentifiée ni modifiée.

Quand cet accès sera rétabli, réessayer le mécanisme prévu et synchroniser l'index ainsi que les chapitres 02, 04, 06, 08 et 11,
en préservant les modifications sans rapport. Distinguer le premier prototype
SetValue montré et essayé, la redécouverte irrégulière après relance, et la
correction WirelessBuddyFlags maintenant appliquée et relue sur l’iPhone en USB.
Ajouter le dédoublonnage des transports : une lecture par téléphone/Watch,
1,283 s et 0,1052 s CPU pour le relevé USB réel, iPhone 81 % et Watch 75 %.
Le paquet Dev (21) reconstruit montre les niveaux et l’accès Wi-Fi actif.
Le débranchement puis deux relances complètes passent : iPhone 86 %, Watch
75 %, connexion réseau seule confirmée, UI relue après chaque nouveau lancement.
Relevés natifs distincts : 3,696 s / 0,2043 s CPU, puis 2,701 s / 0,2011 s CPU
avec notre Dev arrêtée. L’état Wi-Fi reste actif et le bouton de modification
est désactivé sans USB. Le défaut du matin ne se reproduit pas dans ce scénario ;
longue veille, redémarrage des appareils et changement de réseau restent non testés. Ne pas
présenter la fonction comme livrée ni la fiabilité réseau comme établie.
Les preuves réseau sont dans `build/apple-device-wifi-qa/resume-wifi-*.json`.
Préserver les validations anciennes datées et relire les pages après écriture.

Les pages gardent pour l'instant la note antérieure sur `6b207f1` ; elles ne
doivent pas servir de preuve de la dernière correction préparée.
