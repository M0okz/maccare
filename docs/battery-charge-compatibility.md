# Recharge complète prioritaire et compatibilité M1 Max

État du 10 novembre 2026 : **développement local non livré**, branche
`codex/battery-calibration-status`. Aucun remplacement de la copie quotidienne,
aucune activation de charge ni extension de la liste des modèles validés.

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
