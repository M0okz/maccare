# Température GPU M1 — Dev du 9 novembre 2026

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

Correction locale non publiée sur `codex/helper-process-icons`, après MacCare
0.2.14 (16). Paquet `build/gpu-temperature/MacCare.app`, Dev 0.2.14 (11).

## Signalement et lecture

Sur le M1 Max de Gregory, la charge GPU fonctionne mais la température affiche
`— °C`. Le lecteur ne consultait que les événements HID `GPU MTR Temp`.
Le test du point d’entrée `maccare_gpu_temperature` reproduit l’absence de
valeur quand ces événements manquent, même si un capteur GPU SMC valide existe.
C’est une reproduction sur pilote simulé, pas un relevé du M1 Max distant.

HID reste prioritaire. Sans valeur valide, les M1, Pro, Max et Ultra consultent
`Tg05`, `Tg0D`, `Tg0L`, `Tg0T` par le client SMC type 0 en lecture seule.
Le maximum valide est retenu : formats `flt ` et `sp78`, tailles, finitude et
plage `0 < T ≤ 125 °C` contrôlés. Les capteurs absents restent indisponibles.
Aucun capteur CPU ne remplace une température GPU manquante ; aucun catalogue
d’une autre génération n’est deviné.

Identifiants vérifiés dans le
[catalogue Stats épinglé](https://github.com/exelban/stats/blob/a04bc5e629242c9a29a98ef32ed1f5f46a88c874/Modules/Sensors/values.swift),
connexion recoupée avec son [lecteur SMC](https://github.com/exelban/stats/blob/master/SMC/smc.swift).
Ces conventions sont référencées dans `THIRD_PARTY_NOTICES.md` ; aucune nouvelle
bibliothèque n’est embarquée.

## Coût et validation

Le cache de cinq secondes du sampler, hors du fil de l’interface, reste inchangé.
Le repli lit au plus quatre clés, seulement si HID manque et que le modèle est
reconnu, puis ferme sa connexion. Aucun timer, suivi supplémentaire ou commande
de charge/ventilateur n’est ajouté. Le décodeur SMC est partagé avec le repli CPU
existant, dont le comportement est couvert par régression.

`bash app/Tests/SMCWireTests/run.sh` réussit sous AddressSanitizer et
UndefinedBehaviorSanitizer : pilotes simulés, priorité HID, événements absents
ou invalides, séparation CPU/GPU, chaque clé M1, maximum valide, formats,
tailles, permissions, familles inconnues, bornes, fermeture et zéro écriture.
Ce contrôle est ajouté à la CI ; son exécution distante reste à faire après
publication de la branche. Les tests Swift ciblés passent également (28 tests).

Sur le M1 local, HID renvoie 30 °C. Le client SMC type 0 s’ouvre et lit `FNum`,
mais les quatre clés GPU sont absentes sur cette machine. Cela confirme le
maintien du chemin HID et la lecture SMC sans élévation ; **la disponibilité et
la température réelles sur le M1 Max de Gregory restent à confirmer**.

Preuves : `build/gpu-temperature-qa/` (`red.log`, `smc-tests.log`, `swift-tests.log`,
`local-readings.json`, `local-smc-diagnostics.log`, `build.log`, `package.log`,
`validation.json`). Seule la Dev locale est actualisée ; la copie quotidienne
est préservée et aucune release n’est publiée pour cette correction.
