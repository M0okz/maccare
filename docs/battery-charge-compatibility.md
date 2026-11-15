# Recharge complète prioritaire et compatibilité M1 Max

État du 15 novembre 2026 : **développement local non livré**, branche
`codex/m1-max-battery-diagnostics`. Aucun remplacement de la copie quotidienne,
aucune activation de charge ni extension de la liste des modèles validés.

## Relevé réel du M1 Max — 14 novembre 2026

Gregory a exécuté les commandes en lecture seule dans son shell root et transmis
les sorties. Le Mac est `MacBookPro18,4`, macOS **27.2 (26B123)**, avec MacCare
**0.2.26**. Au relevé : secteur présent, batterie **100 %, chargée**, aucune
limite enregistrée (`pmset -g battlimit`), et notification
`com.apple.system.powersources.chargingtofulloverride` à **1**.

Ce relevé distingue une priorité Apple signalée d'une lecture impossible. Dans
le chemin natif 80–100 % de cette version, cette priorité bloque la capture
initiale avant la première écriture et avant l'enregistrement d'une protection.
L'absence de limite enregistrée est cohérente avec ce refus, sans établir à elle
seule l'historique exact des tentatives d'activation.

Le signal ne prouve ni la cause précise de la priorité, ni sa durée restante.
Le fait d'être chargé à 100 % ne suffit pas à déclarer ce signal périmé ou à le
remettre à zéro. Les journaux `powerd`/`PowerUIAgent` et les deux préférences
de limite ont ensuite été lus (voir ci-dessous). Aucun drapeau, réglage de charge,
assistant ou fichier du M1 Max n'a été modifié par cette investigation.

### Deuxième relevé : cause de la demande Apple

Les deux clés `MCLFeatureState` et `mclLimitValue` sont absentes du domaine root
`com.apple.smartcharging.topoffprotection`. Le pilote MacCare sait représenter
cette absence sans inventer une limite ; ce résultat n'est pas en soi une
corruption des préférences ni une preuve d'incompatibilité.

Le diagnostic CLI installé renvoie `supported: true`, `active: false`,
`restoring: false`, `suspended: false`, batterie à 100 %, secteur présent,
charge inactive, température 31,79 °C, 10 cycles, santé annoncée 100 % et
`batteryFault: false`. `supported` confirme une découverte par lecture, pas
un essai de changement de limite ni la validation de la politique avancée.
`recoveryReady: false` appartient au diagnostic CLI indépendant du daemon ; il
ne permet pas de conclure à un défaut de surveillance du service launchd.

Les journaux transmis entre 10:55 et 11:31 indiquent explicitement :

```text
Last DOD0 change 13.6 days ago — charge to full
periodicChargeToFullCheck run gauging mitigation policy
Charge To Full Request: 1
Charge To Full System Level Request:0
```

Ils établissent une demande Apple liée au suivi de la jauge après un ancien
événement DOD0. Ils ne mesurent ni la date du dernier étalonnage complet, ni
la durée restant à cette demande. Les requêtes par pack et au niveau système
ne sont pas confondues : le signal global lu séparément reste l'observation
utilisée par le garde-fou MacCare, à 1 lors du premier relevé.

La ligne de 12:25 `received SOC limit from 41615: <private>` confirme seulement
la réception d'une demande par `powerd`. La valeur est masquée et l'identité du
processus n'a pas été relevée ; cette ligne ne prouve ni une limite enregistrée
et appliquée, ni un auteur MacCare, ni une prise de contrôle réussie.

La prochaine lecture utile pour la compatibilité avancée est la matrice SMC,
désormais accessible par le CLI de développement ci-dessous sans ouvrir l'app.
Dans la version installée, elle reste accessible au bouton **Afficher le diagnostic
de compatibilité…**, si l'assistant est déjà activé.
Elle peut montrer si `CHIE` est lisible et quelles anciennes méthodes
sont refusées. Cette matrice ne teste aucune écriture. Ne pas activer ou
réinstaller l'assistant pour la recueillir dans la phase actuelle, limitée à
la lecture. Aucune modification du signal Apple n'est proposée.

Ce modèle reste hors de la liste de validation de la méthode avancée. Une
lecture de la notification n'est pas un essai de maintien, de reprise ou de
restauration. Ces validations et la disponibilité réelle du contrôle d'adaptateur
sur le M1 Max restent à établir.

Le correctif du 10 novembre est repris sans conflit sur la branche isolée
`codex/m1-max-battery-diagnostics`, commit `4fa800c`, depuis `origin/main`
`ea8305a`. Cette reprise n'est ni une publication ni une installation ; la version
0.2.26 du M1 Max conserve donc encore son ancien message d'étalonnage.

## Message corrigé

La notification Apple `com.apple.system.powersources.chargingtofulloverride`
fournit un état de priorité de recharge complète. Elle ne permet pas à MacCare
d'affirmer la cause exacte de cette priorité.

Avant cette correction, une lecture impossible et une priorité confirmée
produisaient toutes deux une erreur annonçant un étalonnage en cours.
Le pont C, le pilote natif 80–100 %, le pilote de politique avancée et les
contrôles de décharge distinguent maintenant :

| État lu | Résultat |
| --- | --- |
| Inactif | Les contrôles existants restent applicables. |
| Actif | Code natif `-8` : « macOS donne la priorité à une recharge complète de la batterie. La protection attend la fin de cette opération. » |
| Illisible | Code natif `-9` : « MacCare ne parvient pas à vérifier si macOS impose une recharge complète. Réessayez dans quelques instants. » |

La politique avancée utilise respectivement les erreurs `appleOverride` et
`unknownAppleOverride`. Les erreurs avant et après écriture restent bloquantes ;
un échec après écriture conserve les obligations de restauration existantes.
L'absence d'information n'autorise aucune nouvelle mutation. Une restauration
déjà satisfaite garde son comportement sans réécriture.

## Deux niveaux de prise en charge

Apple documente la [limite de charge 80–100 %](https://support.apple.com/en-us/102338)
pour les Mac Apple silicon avec macOS 26.4 ou ultérieur. Le M1 Max relève de
cette famille, mais la disponibilité et l'état doivent être lus sur le Mac
concerné. La capture de Gregory montre une méthode native proposée et un refus
d'accès aux anciens contrôles matériels ; elle ne distingue pas une priorité
de recharge réelle d'un état illisible.

La méthode avancée de MacCare (limites 50–100 %, mode Voile et pause thermique)
reste limitée à `MacBookPro17,1`, seul modèle validé par le projet. Le M1 Max
n'est pas déclaré incompatible par son processeur : **il est hors de cette
liste de validation**. Les sources batterie de `main` relues le 10 novembre
au commit `3d2d81c` sont identiques à la base de ce correctif sur ce périmètre.

La piste d'extension est le pilote existant `NativeChargePolicyHardware` :
préférences de charge Apple, notification de rechargement, relecture de la
limite enregistrée, journal de récupération et contrôle d'adaptateur.
La [source Ampere consultée](https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/Shared/NativeChargeLimit.swift)
décrit le même mécanisme de préférences ; cela ne constitue pas une validation
matérielle du pilote MacCare sur le M1 Max.

La méthode MacCare dépend du contrôle d'adaptateur pour sa transition d'entrée
et sa restauration. Supprimer seulement la condition de modèle, ou utiliser
une liste de limites retournée par PowerUI comme preuve de maintien physique,
ne valide pas cette dépendance. Les incidents précédents, liés à une limite
écrite sous le niveau courant et à la puissance du chargeur, restent pertinents.
Voir [les observations matérielles datées](native-charge-policy.md).

## Diagnostic disponible

Dans **Batterie → Protection de la batterie → Fonctionnement et compatibilité →
Afficher le diagnostic de compatibilité…**, la réponse existante du helper
conserve ses champs `method`, `helperUID` et `smc`, et ajoute `compatibility` :

- modèle exact et version macOS, UID effectif ;
- admissibilité de la version macOS, modèle validé ou non, présence de l'interface avancée ;
- `fullChargeOverride` : `inactive`, `active` ou `unknown` ;
- capacités détectées, dont backend et contrôle d'adaptateur si accessibles ;
- limite native actuelle et valeurs proposées par Apple, erreurs de lecture séparées.

Une découverte qui échoue expose `controlReadError` et omet `capabilities`.
Elle n'invente pas un backend disponible. La réponse ne contient ni numéro de
série, ni UUID, ni identité de récupération. Les sondes ne capturent pas de
journal et n'appellent aucun setter de charge ou d'adaptateur.

Le binaire de développement offre aussi une commande indépendante :

```sh
"/chemin/absolu/vers/MacCareHelper" --battery-compatibility-diagnostics
```

Sans privilèges, `effectiveUID` et `controlReadError` expliquent les limites
de la sonde ; ne pas assimiler ce résultat au diagnostic du helper système UID 0.
L'ancien `--battery-diagnostics` conserve son format. La nouvelle commande
quitte avant le démarrage du daemon et du contrôleur.

### Diagnostic complet dans Ghostty — ajout du 15 novembre

Le **nouveau helper** accepte `--battery-full-diagnostics`. Il imprime un JSON
sur la sortie standard puis termine ; il ne contacte pas le service installé,
ne crée pas de journal de récupération et ne modifie aucun réglage de charge.
Ce mode partage le collecteur `BatteryFullDiagnostics` avec le diagnostic XPC.
Les champs existants `method`, `helperUID`, `smc`, `compatibility` sont conservés ;
`snapshot` ajoute la télémétrie de batterie. Les clés optionnelles indisponibles
peuvent être absentes.

La matrice comprend `bfF0`, `bfD0`, `bfE0`, `CHTE`, `CH0B`, `CH0C`, `CH0I`,
`CH0J`, **`CHIE`** et `CHLS`, pour deux transports et deux modes de handshake :
40 tentatives, dont quatre pour `CHIE`. Chaque ligne conserve `result`, `size`,
`type` et les quatre premiers octets bruts en hexadécimal. Un `result` non nul
est une erreur de lecture : ne pas interpréter ses octets nuls comme une valeur
matérielle, ni une lecture réussie comme une validation d'écriture.

Dans Ghostty, après mise à disposition du **nouveau binaire** sur le Mac cible :

```sh
sudo "/chemin/absolu/vers/le/nouveau/MacCareHelper" --battery-full-diagnostics
```

Dans le shell root déjà ouvert sur le M1 Max, omettre `sudo`. Aucun fichier de
sortie n'est créé par cette commande. L'UID 0 permet les lectures privilégiées ;
sans lui, les refus restent visibles dans le JSON.

**Ne pas utiliser cette option avec MacCare 0.2.26** : cette version ne la connaît
pas et son ancien traitement des arguments peut démarrer le daemon. Le nouveau
helper refuse les options inconnues ou combinées (code 2), affiche l'aide avec
`--help`, et conserve les formats des deux anciens diagnostics. Code 0 : rapport
produit, y compris avec erreurs de lecture ; code 1 : échec d'encodage du rapport.
L'absence d'argument reste réservée au service launchd.

Validation locale du 15 novembre :

- helper arm64 compilé ; 170 tests batterie réussis ;
- fixtures SMC et PowerUI sous ASan/UBSan réussies, dont la matrice complète sans
  écriture SMC et les sondes natives sans setter ;
- `bash app/Tests/BatteryDiagnosticsCLI/run.sh /chemin/vers/le/helper-developpement`
  vérifie le JSON réel, les quatre lignes `CHIE`, les formats anciens, l'aide et
  les arguments refusés. Un garde de test interposé bloque les écritures SMC,
  modifications de préférences, posts de notification et démarrage batterie ;
- exécution uniquement sans privilèges sur le M1 local. Aucun essai CLI root
  ni matériel sur le M1 Max, aucune installation ni publication.

Artefact local : `build/swift-tests/arm64-apple-macosx/debug/MacCareHelper`.

### Helper autonome préparé pour transfert SSH

Le 15 novembre, une variante release arm64 est préparée dans
`build/battery-diagnostics/MacCareBatteryDiagnostics-20261115`, accompagnée d'un
`LIRE-MOI.md` avec les commandes exactes de copie, exécution et suppression,
et d'une empreinte `.sha256`. Elle est signée Developer ID avec hardened runtime,
sans entitlement supplémentaire ; elle n'est pas notariée. Toutes ses dépendances
sont des bibliothèques système. Aucun outil de développement n'est requis sur la cible.

Cette variante se compile avec `-Xswiftc -DMACCARE_DIAGNOSTICS_ONLY`. Le listener
XPC, le démarrage du service batterie et la boucle du daemon sont exclus du point
d'entrée ; sans argument, elle quitte avec le code 2. Le helper de l'application
conserve son comportement launchd normal. La CI couvre les deux variantes.

Le test CLI avec garde interposé passe sur la variante release non signée pour
distribution, y compris l'appel sans argument. Après signature, le fichier exact
de transfert a été exécuté sans privilèges sur le M1 local : JSON valide,
40 tentatives SMC dont quatre CHIE, aide et sorties d'erreur conformes. Signature
stricte vérifiée. Empreintes des exécutables de la copie utilisateur inchangées.
La CI distante, l'exécution root et le M1 Max ne sont pas testés dans cette étape.

Le transfert prévu copie seulement le binaire dans le dossier personnel du compte
SSH `gnarcin` ; la commande le vérifie, lance `sudo … --battery-full-diagnostics`
puis supprime cette copie si la commande réussit. Aucun remplacement de MacCare,
enregistrement de service ou écriture de réglage de charge. Aucun transfert n'a
encore été exécuté par Codex.

## Validation nécessaire sur le M1 Max

1. Relever modèle, macOS, version MacCare, chargeur et diagnostic du helper UID 0 ;
   comparer les états signalés par macOS et vérifier qu'un autre contrôleur ne
   possède pas la charge. Ne pas modifier les réglages d'un autre outil automatiquement.
2. Confirmer d'abord la limite native 80–100 % en l'absence de priorité Apple,
   avec relecture et observation de la charge physique.
3. Pour la méthode avancée, vérifier en lecture seule l'interface PowerUI, les
   préférences initiales, les limites enregistrées et l'accès à `CHIE`.
4. Dans une campagne de développement sur ce Mac, vérifier maintien, reprise,
   désactivation, restauration après interruption et veille. Relever secteur,
   courant et niveau réel ; respecter les garde-fous interdisant une limite
   sous le niveau courant pendant un maintien. Vérifier la restauration du
   journal et documenter le chargeur utilisé.
5. Étendre ensuite la liste au modèle exact observé, avec des preuves matérielles
   datées. Les simulations M1 Max de cette correction ne remplissent pas ce critère.

## Vérifications de cette correction

- Régression rouge avant correction sur l'erreur renvoyée et son message,
  puis verte : capture, changement de limite, restauration, décharge et contrôleur.
- 169 tests du module batterie réussis ; pilotes injectés, aucun setter matériel réel.
- Frontière Objective-C PowerUI sous ASan/UBSan réussie, aucun setter natif invoqué.
- Helper de développement compilé et nouvelle commande exécutée sans privilèges
  sur le M1 local : état Apple inactif, limite 80 %, valeurs 80/85/90/95/100.
- Le M1 Max distant, les écritures réelles, une priorité Apple réelle, la QA
  visuelle de l'app et une installation utilisateur ne sont pas testés ici.

Preuves locales : `build/battery-calibration-qa/`,
`build/battery-calibration-red.log` et `build/battery-calibration-green.log`.
