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

## Préparation du helper autonome — 15 novembre 2026

Une variante release arm64 réservée au diagnostic est préparée sous
`build/battery-diagnostics/`, avec README de transfert SSH/exécution/suppression
et SHA-256. Signature Developer ID, hardened runtime, sans entitlement, non
notariée. Dépendances système uniquement. `MACCARE_DIAGNOSTICS_ONLY` exclut
le démarrage XPC et batterie, même sans argument (code 2) ; le helper distribué
dans l'app garde son comportement normal. Le test de cette variante est ajouté
à CI ; aucun lancement distant de CI.

Contrôles locaux : release avec garde de lecture seule, puis exécution du fichier
signé, 40 lignes SMC/4 CHIE, aide et erreurs d'arguments ; signature stricte valide.
Empreintes des deux exécutables utilisateur inchangées. Aucun transfert ou essai
root/M1 Max. La procédure transmise copie seulement le binaire temporaire dans
le home SSH, affiche le JSON et supprime la copie après réussite.

Nouvel essai de l'accès documentaire prévu : même échec `Bitwarden status failed`.
Synchronisation des pages 06/08/11 toujours en attente, aucun contournement.

## Diagnostic distant reçu — 15 novembre 2026

Gregory a transmis la sortie complète du helper autonome sur MacBookPro18,4,
macOS 27.2.0, UID 0. Les quatre lectures CHIE réussissent, taille 1, type hex_,
valeur 00 ; backend d'adaptateur moderne détecté. Toutes les autres clés SMC
échouent. Le champ hardwareAccessDenied décrit la découverte du contrôle de
charge SMC ; il ne décrit pas un refus de tout accès matériel, puisque CHIE
est lisible. La lecture seule ne valide aucune écriture ni restauration.

Limite native sélectionnée, valeurs 80/85/90/95/100 proposées, limite désactivée
à 100. Priorité Apple toujours active. Interface de politique avancée présente,
modèle toujours non validé. Batterie à 74 %, hors secteur, 11 cycles, santé
annoncée 100 %, 32,79 °C, sans défaut signalé. Ne pas présenter ce signal comme
la preuve d'une recharge ou d'un étalonnage en cours hors secteur.

La validation CLI root distante est maintenant étayée par la sortie utilisateur.
Aucun contrôle physique testé, aucune extension de la liste des modèles, aucune
modification du M1 Max par Codex. Document source actualisé et relevé JSON conservé
localement sous build/battery-diagnostics/m1-max-user-report-20261115.json.
Nouvelle tentative documentaire : même échec Bitwarden status failed. Outline
reste à synchroniser.

## MacCare Dev 0.2.28 — préparation M1 Max

Base actualisée sur 0.2.27 (`83099d7`). Nouveau mode de build
`MACCARE_M1_MAX_BATTERY_TRIAL=1` limité au MacBookPro18,4 : sélection de la
politique native avancée et conservation des garde-fous CHIE/journal/priorité
Apple. La liste matériellement validée reste inchangée ; les builds ordinaires
gardent le comportement natif 80–100 % sur ce modèle. Le diagnostic distingue
build d'essai, éligibilité du modèle et validation matérielle.

Écran et confirmation indiquent « en validation ». Refus SMC formulé comme un
refus de la méthode directe, pas de tous les accès matériels. Packaging refusant
le mélange de modes et la publication d'un build d'essai dans le flux public.
Paquet local MacCare Dev 0.2.28 (9), Developer ID, non notarié, sans flux Sparkle.

174 tests batterie, 19 tests de packaging, fixtures C/Objective-C ASan/UBSan,
CLI avec garde de lecture seule et audit runtime sans outils développeur réussis.
Paquet signé et métadonnées vérifiés ; diagnostic signé exécuté sans privilèges
sur M1 local ; exécutables utilisateur inchangés. Aucun test physique distant,
aucune installation ni publication. Source détaillée et plan de validation :
`docs/m1-max-validation-0.2.28.md`.

Accès Outline réessayé : `Bitwarden status failed`. Pages 06/08/11 toujours à
synchroniser ; aucune synchronisation annoncée.

## Confusion entre la version publique et le paquet de validation

Gregory signale les anciens messages après installation de « 0.28 ». Vérification
du tag public `v0.2.28` (`3399a6e`, publié le 15 novembre à 09:15 Paris) : les deux
textes de la capture sont toujours présents et la méthode avancée reste réservée
au modèle validé précédent. Ce tag ne contient pas les correctifs de cette branche.
L'archive locale MacCare Dev 0.2.28 (9), issue de `12233bb`, a été revérifiée :
anciens textes absents, nouveaux textes et bannière de validation présents.

Le numéro 0.2.28 réutilisé pour l'essai a créé une ambiguïté de livraison. La
documentation locale distingue désormais explicitement le paquet Dev de la
mise à jour publique. L'identité du processus réellement lancé sur le M1 Max
n'est pas vérifiée directement : tentative SSH en lecture seule vers l'adresse
utilisée dans le relevé précédent, délai de connexion dépassé. Aucun ancien
helper n'a été exécuté avec une option inconnue, aucun changement distant.


## Livraison publique 0.2.29 — 15 novembre 2026

**Livré dans MacCare 0.2.29 (build 31)** après fusion de la PR #38, tag sur
`4ca502febbc86b4c4e735212b47706e3b873e4aa`. Ce statut remplace les mentions
historiques « développement non livré » pour le correctif et le diagnostic.
La décision explicite de Gregory autorise la distribution du mode M1 Max en
validation ; elle ne transforme pas MacBookPro18,4 en modèle matériellement
validé. La priorité Apple active ou illisible continue de bloquer les écritures.
La publication n'installe pas la version chez Gregory.

Pages à actualiser : index, architecture, batterie, développement, publication,
Sparkle et dépannage. Conserver les anciens relevés datés. Décrire les deux
indicateurs de build, le garde de packaging, le diagnostic CLI et les deux
erreurs distinctes de priorité Apple. La CI prend en charge Bash 3 et les
runners sans batterie. Références, tests et preuves publiques :
[livraison 0.2.29](release-integration-0.2.29.md).

Les dix pages du site public sont livrées et relues. Outline reste non synchronisé :
l'accès prescrit par le helper Homelab échoue avec `Bitwarden status failed`.
Aucun accès retiré n'a été contourné.

## État Apple actualisable — 22 novembre 2026, non livré

Correctif local après `63843da`, branche `codex/m1-max-battery-diagnostics` :
statut Apple distinct de l’éligibilité du modèle, blocage expliqué avant
activation, actualisation en lecture seule, retrait limité d’une ancienne erreur
Apple après relecture favorable, diagnostic de jauge sans identifiants.
Voir [le détail et les limites](m1-max-apple-charge-state.md).

Pages à actualiser : batterie, développement et dépannage. Préserver le statut
historique livré de la 0.2.29. Ne pas annoncer une validation matérielle M1 Max
ni un déblocage durable ; le résultat de la réinitialisation proposée est inconnu.

Accès prescrit retenté avec `homelab.py bw-exec --project <worktree> -- /usr/bin/true`.
Échec effectif : `Homelab environment failed (file, format, command or timeout);
no values displayed`. Aucun accès Outline acquis, aucune page modifiée. Cette
note reste nécessaire pour reprendre la synchronisation lorsque l’accès revient.
