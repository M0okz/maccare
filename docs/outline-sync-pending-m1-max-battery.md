# Synchronisation Outline en attente — relevé M1 Max

14 novembre 2026. Pages concernées : **06 — Batterie, CPU, RAM et réseau**
et **11 — Dépannage, validations et historique des décisions**.

Le relevé transmis par Gregory depuis son shell root confirme :

- modèle `MacBookPro18,4` ; macOS 27.2, build 26B123 ; MacCare 0.2.26 ;
- secteur présent et batterie chargée à 100 % ;
- aucune limite de charge enregistrée ;
- notification Apple de recharge complète prioritaire à 1.

Deuxième relevé transmis : les deux préférences root `MCLFeatureState` et
`mclLimitValue` sont absentes ; le diagnostic CLI signale une méthode disponible
en lecture (`supported: true`) sans protection active ni restauration, à 100 %
sur secteur, sans charge et sans défaut signalé. Santé annoncée 100 %, 10 cycles,
31,79 °C. Ce relevé n'est pas un test de changement de limite. Le booléen
`recoveryReady` du CLI ne décrit pas le service launchd chargé.

Journaux Apple à 10:55–11:31 : ancien changement DOD0 de 13,6 jours, demande de
recharge complète par la politique de suivi de jauge, requête par pack à 1 et
requête au niveau système à 0. La cause de la demande Apple est donc documentée ;
sa durée restante et sa levée à 100 % ne sont pas établies. La ligne de 12:25
`received SOC limit` contient une valeur masquée et ne démontre pas l'application
d'une limite. Lecture SMC `CHIE` et campagne matérielle avancée encore nécessaires.

L'état n'est pas illisible dans le premier relevé. Le garde-fou du chemin natif de
MacCare refuse l'activation avant écriture lorsque ce signal est actif. La cause
est maintenant documentée par les journaux ; une batterie chargée ne suffit pas
à autoriser une remise à zéro du signal. Aucune modification sur le M1 Max
n'est autorisée pour cette phase.

Le correctif de message et le diagnostic du 10 novembre sont repris au commit
`4fa800c` sur `codex/m1-max-battery-diagnostics`, base `ea8305a`, dans un worktree
distinct. Le chantier À propos et la réorganisation locale sont préservés.
Pas de publication, d'installation ni d'extension de la liste des modèles validés.
Pas de maintien/reprise/restauration physiquement testé sur ce M1 Max.

Document source : `docs/battery-charge-compatibility.md`.

L'accès Outline reste indisponible par le mécanisme configuré : lors de la
réorganisation locale précédente du même jour, le wrapper Bitwarden a confirmé
que l'accès personnel était retiré au profit d'Infisical ; aucune configuration
Infisical exploitable n'avait été trouvée. Ce retrait n'est pas contourné.
Lire les pages, ajouter le relevé daté sans effacer les limites historiques, puis
relire après écriture lorsque le nouvel accès documentaire sera disponible.

## Ajout du 15 novembre 2026 — commande complète sans interface

État : développement local non livré sur `codex/m1-max-battery-diagnostics`.
Ajouter également la page **08 — Développement, build local et tests** aux pages
à synchroniser. Le helper expose `--battery-full-diagnostics` : même collecteur
que le diagnostic XPC, télémétrie, compatibilité et 40 tentatives de lecture SMC
dont quatre `CHIE`. Pas de démarrage du service, de capture de récupération ni
de setter. Les anciennes options gardent leur format ; arguments inconnus ou
combinés refusés avant démarrage. Aide avec `--help`.

La commande documentée exige le nouveau binaire. Ne pas passer cette option à
la 0.2.26 installée : l'ancien traitement des options inconnues peut démarrer
le daemon. Aucun transfert, installation, lancement ou changement sur le M1 Max.

Validation : helper arm64 compilé ; 170 tests batterie ; fixtures C SMC et
Objective-C PowerUI sous ASan/UBSan ; smoke CLI réel sans privilèges sur M1 local,
avec garde interposé contre écritures SMC/préférences/notifications et démarrage
du service batterie. Le contrôle CLI est ajouté à CI, non exécutée à distance.
Ni lecture CLI root sur M1 Max ni maintien/reprise/restauration validés.

Nouvel essai de l'accès prévu le 15 novembre : `homelab.py bw-exec --project`
échoue avec `Bitwarden status failed; check login, configured secret and server access`.
Aucune page Outline modifiée ; synchronisation toujours en attente.
