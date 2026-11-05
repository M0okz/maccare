# Politique de charge Apple sur les nouveaux firmwares

État : préparée pour la version 0.2.2, disponible seulement une fois sa release publiée.
La version 0.2.1 ne contient pas cette méthode.

## Résultats sur matériel

Validé le 4 novembre 2026 sur un seul Mac : MacBookPro17,1 (M1), macOS 27.0.1, firmware
20457.1.29, chargeur 65 W, avec un paquet Developer ID local. L'activation est limitée à
ce modèle ; les autres gardent la limite Apple de 80 à 100 %.

| Essai | Résultat observé |
| --- | --- |
| Activation à 78 % avec la batterie à 80 % | Niveau maintenu à 80 %, secteur tenu |
| Décharge vers 78 % | Secteur rendu en moins d'une seconde à l'arrivée, sans toucher au câble |
| Maintien à 78 % et 79 % | 0 mA, chargeur couvrant toute la consommation, 51 minutes sans changement |
| Limite atteinte en charge | Arrêt, 0 mA, secteur tenu |
| Limite abaissée en pleine charge | Enregistrée en moins d'une seconde, secteur tenu |
| Câble débranché puis rebranché | Maintien repris sans erreur |
| Veille de 15 minutes à 78 %, limite d'origine 80 % | Limite 78 conservée, capacité inchangée |
| App tuée | Limite d'origine rétablie en 85 secondes, secteur tenu |
| Désactivation à 81 %, limite d'origine 80 % | Restauration différée, secteur toujours présent après 90 secondes |
| Réactivation pendant cette attente | Session reprise, limite maintenue |
| Assistant relancé pendant cette attente | Attente reprise depuis le journal, sans erreur |
| Mode Voile, batterie dans la plage | Pause à 81 % pour une plage 80–82 %, sans charge |
| Mode Voile, batterie à la borne basse | Charge relancée, arrêt à la borne haute, secteur tenu |
| Pause thermique, seuil dépassé en pleine charge | Charge arrêtée, limite ramenée au niveau courant, secteur tenu |
| Reprise thermique | Automatique à 2 °C sous le seuil, après 30 minutes de pause |
| Recharge ponctuelle, puis annulation | Limite 100 enregistrée en 90 secondes, annulation en moins d'une seconde |
| Fichier de l'assistant remplacé pendant une attente | Nouvel assistant actif en 3 secondes, reprise depuis le journal |

Non validés : fin réelle d'une restauration différée, cycle complet d'étalonnage,
programmations, veille d'une nuit, arrivée à 100 %, autres modèles et firmwares. La reprise du
mode Voile a été provoquée en décalant la plage, pas après une vraie baisse sur batterie. Le
dépassement thermique a été provoqué en abaissant le seuil, sans échauffement réel. Les
décharges ont été observées avec un chargeur annoncé à 65 W, les essais suivants à 30 W.

## Limite sous le niveau de charge

**Une limite enregistrée sous le niveau de charge coupe l'entrée secteur sur ce Mac.**
Reproduit le 4 novembre : limite 80 enregistrée avec la batterie à 81 %, sans action sur
l'adaptateur. Sept secondes plus tard, le Mac passe sur batterie, câble branché, et l'entrée
tombe à 0 mW. Le secteur n'était pas revenu 24 minutes plus tard, avec la batterie déjà
descendue à 79 %, et n'est revenu qu'après une reconnexion physique.

Un premier maintien à 31–32 %, sans transition d'entrée, avait échoué ainsi : sa cible
s'était enregistrée en retard, sous le niveau atteint entre-temps. MacCare applique donc
ces règles :

- une limite n'est jamais écrite sous le niveau de charge, sauf décharge demandée avec
  l'adaptateur déjà coupé ;
- un maintien fixe la limite au niveau courant, ou 3 points au-dessus tant que la batterie
  charge : sa cible peut s'enregistrer une minute plus tard, sous un niveau qui a monté ;
- une transition d'entrée de 500 ms via `CHIE` suit chaque changement sur secteur, et
  l'enregistrement a alors pris moins d'une seconde, contre 67 secondes sans elle ;
- la restauration attend que la batterie soit redescendue à la limite d'origine ;
- une perte du secteur dans les 15 secondes suivant un changement arrête la session.

Le lien entre la transition et la rapidité d'enregistrement est observé, sans que chaque
facteur ait été isolé. Une limite abaissée sous le niveau de charge depuis les Réglages
Système peut produire la même coupure, hors du contrôle de MacCare.

L'API permettant de choisir les flags exige un entitlement privé Apple, et le registre
`CHLS` renvoie `kIOReturnNotPrivileged` au helper root. Le flag Drain reste donc actif,
ce qui est compatible avec tous les maintiens ci-dessus.

## Méthode distincte du curseur PowerUI

Le pilote existant `NativeChargeDriver` conserve sa liste fournie par PowerUI,
ses bornes 80–100 et ses contrats de restauration. La nouvelle méthode utilise
un pilote séparé, `NativeChargePolicyDriver`, exécuté uniquement par l’assistant
root. Elle possède deux clés du domaine `com.apple.smartcharging.topoffprotection` :

- `MCLFeatureState` : activation de la politique ;
- `mclLimitValue` : cible demandée au service Apple.

Le pilote écrit les deux clés ensemble avec `CFPreferencesSetMultiple`, synchronise,
publie `com.apple.smartcharging.defaultschanged` et relit la paire exacte. Il
n’accepte aucun domaine, chemin ou nom de notification fourni par le client XPC.
Les préférences sans rapport, dont la recharge optimisée, restent hors de ce pilote.

Le pourcentage affiché est lissé : il a indiqué 80 alors que la capacité restante valait
77,4 %, et une décharge de 2 points a pris environ 26 minutes à faible consommation.

Ce mécanisme est documenté par le projet MIT
[Ampere au commit 843498d7](https://github.com/az-code-lab/ampere/tree/843498d7beb711c0e1b18e48c8520debe67f6e3f),
notamment [sa définition](https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/Shared/NativeChargeLimit.swift)
et [son assistant](https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/SMCWriter/main.swift).
MacCare utilise une implémentation indépendante avec validation et restauration
plus strictes.

## Configuration et application effective

Une écriture de préférences réussie confirme la configuration demandée.
`pmset -g battlimit` fournit séparément la cible enregistrée par macOS.
Les relevés de batterie indiquent ensuite si la charge physique s’est arrêtée.
Ces trois observations ne sont pas interchangeables.

Le pilote ne bloque pas la queue de batterie pendant la propagation de la limite.
La lecture `pmset`, exclusivement en lecture, est bornée en durée et en taille ;
une sortie inconnue ou contradictoire est une erreur, pas une absence de limite.
Le contrôleur suit le délai de propagation sans renouveler ce délai à chaque
variation de pourcentage ou simple relecture du statut.

Apple documente une [reprise native après une baisse supérieure à cinq points](https://support.apple.com/en-us/102338).
Un plafond fixe n’est donc pas à lui seul un mode Voile personnalisable ou une
pause thermique : leur reprise repose sur le maintien logiciel. La calibration décidée
par macOS garde la priorité ; MacCare ne tente pas de la contourner.

## Décharge

La décharge volontaire ferme d'abord la coupure d'adaptateur, écrit la cible, puis rouvre
la coupure à l'arrivée, cible déjà en place. Le Mac se déclare alors sur batterie, ce qui
n'interrompt pas le cycle.

**Retirée en 0.2.5, de retour en 0.2.6 sans restriction de chargeur.** Essais du 5 novembre 2026
sur ce Mac, avec la même séquence :

| Décharge | Alimentation | Limite retirée par macOS à 300 s | Secteur |
| --- | --- | --- | --- |
| 87 → 85 %, sous forte charge | 30 W, 12 V | Oui | Pas revenu sans reconnecter le câble |
| 58 → 57 %, au repos | 30 W, 12 V | Oui | Absent 49 minutes plus tard, sans reconnexion |
| 54 → 53 %, au repos | 65 W, 20 V | Non, 4 min 23 s | Revenu seul |
| 53 → 51 %, au repos | 65 W, 20 V | Oui | Revenu seul |

Le retrait de la limite n'explique donc pas seul l'échec. Le rôle de l'alimentation est probable,
mais l'échantillon est faible et la décharge sous forte charge sur 65 W n'a pas été essayée. Câble
branché et secteur perdu, ni une impulsion sur la coupure ni une nouvelle limite n'ont rétabli
le secteur. L'app demande alors de reconnecter le câble au bout de 3 minutes.

## Veille

La limite enregistrée reste en place pendant la veille, sinon un Mac branché remonterait
chaque nuit au-delà d'une limite sous 80 %. Une coupure ouverte est refermée, une recharge
ponctuelle ou un cycle restaure les réglages, et une app qui ne revient pas dans le délai
de grâce après le réveil les restaure aussi.

## Restauration

Avant toute mutation, le contrôleur conserve un journal durable identifié par
machine et par méthode. Le journal v5 possède aussi la coupure d'adaptateur, rouverte
avant toute autre étape, y compris après un plantage pendant une transition ; un ancien
journal v4 reste lisible sans y toucher. La nouvelle paire mémorise la présence et le type des
valeurs : une clé initialement absente doit être supprimée à la restauration ;
un booléen n’est pas transformé implicitement en entier.

Éteindre uniquement la préférence ne suffit pas à retirer une limite enregistrée.
La libération passe par les méthodes contrôlées du client PowerUI, avec validation
de leur ABI et des résultats. Les préférences d’origine sont ensuite remises et
relues. Une erreur, une restauration encore en cours ou un journal invalide ne
permettent ni d’effacer le journal ni de choisir silencieusement un autre backend.

Si la batterie dépasse la limite d'origine, la restauration est différée : le niveau courant
reste maintenu jusqu'à ce qu'elle y soit redescendue, en général sur batterie. Ce n'est pas
une erreur, une nouvelle session peut démarrer sans remplacer l'original du journal, et la
mise à jour de l'assistant attend la fin de cette restauration.

Pendant cette attente, l'assistant reste actif. Si une mise à jour remplace son fichier, les
clients ne peuvent plus le vérifier : il restaure donc ce qu'il possède puis se termine entre
deux opérations, et launchd le relance depuis le nouveau paquet, qui reprend le journal.

## Vérifications

Les tests du pilote utilisent des stores, clients et lecteurs injectés. Ils
couvrent types, absences, synchronisation, notification, écriture partielle,
relecture, libération et parsing des registrations. Ils n’appellent aucune
préférence root ni aucun matériel réel. Les tests du contrôleur couvrent le
journal avant mutation, les transitions, la veille et les délais ; les essais
matériels et les versions macOS vérifiées doivent être consignés séparément.

`bash app/Tests/PowerUIBridgeTests/run.sh`, à exécuter sans sudo, contrôle aussi
l’ABI des méthodes de libération, les lectures doubles incohérentes et le refus
des mutations hors du helper root. Ce test ASan/UBSan utilise des clients factices
et n’appelle aucun setter natif.
