# Politique de charge Apple sur les nouveaux firmwares

État : en développement sur `codex/battery-native-policy`. Les tests logiciels
ne constituent pas une validation matérielle. La version utilisateur 0.2.1
ne contient pas cette méthode.

**Validation matérielle échouée le 4 novembre 2026.** Sur le M1 de test sous
macOS 27.0.1, la cible 50 % a été enregistrée et la limite initiale 80 % a été
restaurée. Mais l'entrée dans le maintien 30–50 % vers 31–32 % a été suivie
d'une perte du secteur, câble resté connecté selon l'utilisateur. Le secteur
n'est revenu qu'après sa reconnexion. Ce chemin ne valide donc ni le mode Voile
ni la pause thermique. Son activation en découverte standard est désactivée ;
le candidat reste disponible pour restaurer un journal existant. Les sélections
injectées des tests ne constituent pas une option d'activation dans l'app.

La copie utilisateur a été remise à sa version signée 0.2.1 d'origine et à sa
configuration 80 %, sans mode Voile. Aucun tag ni release 0.2.2 n'est publié.
Les paquets locaux 0.2.2 notariés utilisés pour l'essai ne sont pas des livraisons.

L'analyse du système présent montre que le chemin MCL de PowerUI utilise le
flag Drain. L'API permettant d'en choisir les flags exige un entitlement privé
Apple ; root ne suffit pas. Le diagnostic en lecture seule du registre CHLS
renvoie aussi `kIOReturnNotPrivileged` avec le helper UID 0, sur les deux transports,
avec et sans ouverture explicite. Aucun accès en écriture à ce registre n'a été
tenté. Une méthode de pause sans décharge accessible au helper reste à établir.

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

Ce mécanisme est documenté par le projet MIT
[Ampere au commit 843498d7](https://github.com/az-code-lab/ampere/tree/843498d7beb711c0e1b18e48c8520debe67f6e3f),
notamment [sa définition](https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/Shared/NativeChargeLimit.swift)
et [son assistant](https://github.com/az-code-lab/ampere/blob/843498d7beb711c0e1b18e48c8520debe67f6e3f/Sources/SMCWriter/main.swift).
MacCare utilise une implémentation indépendante avec validation et restauration
plus strictes. Cette référence ne prouve pas que le binaire actuel d’AlDente
utilise exactement le même chemin.

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
pause thermique. Le maintien logiciel et son réarmement doivent être testés
séparément, avec prise en compte de la latence de l’agent. La calibration décidée
par macOS garde la priorité ; MacCare ne tente pas de la contourner.

## Restauration

Avant toute mutation, le contrôleur conserve un journal durable identifié par
machine et par méthode. La nouvelle paire mémorise la présence et le type des
valeurs : une clé initialement absente doit être supprimée à la restauration ;
un booléen n’est pas transformé implicitement en entier.

Éteindre uniquement la préférence ne suffit pas à retirer une limite enregistrée.
La libération passe par les méthodes contrôlées du client PowerUI, avec validation
de leur ABI et des résultats. Les préférences d’origine sont ensuite remises et
relues. Une erreur, une restauration encore en cours ou un journal invalide ne
permettent ni d’effacer le journal ni de choisir silencieusement un autre backend.

## Vérifications

Les tests du pilote utilisent des stores, clients et lecteurs injectés. Ils
couvrent types, absences, synchronisation, notification, écriture partielle,
relecture, libération et parsing des registrations. Ils n’appellent aucune
préférence root ni aucun matériel réel. Les tests du contrôleur couvrent le
journal avant mutation, les transitions, la veille et les délais ; les essais
matériels et les versions macOS vérifiées doivent être consignés séparément.

Le contrôle réel a aussi révélé deux défauts corrigés : une attente normale de
restauration ne devient plus une erreur persistante, et un maintien à l'intérieur
de la plage ne prétend plus que sa borne haute est atteinte. Une régression
vérifie que le candidat ayant échoué ne peut plus être sélectionné par défaut,
tout en restant disponible pour la récupération de son ancien journal.

`bash app/Tests/PowerUIBridgeTests/run.sh`, à exécuter sans sudo, contrôle aussi
l’ABI des méthodes de libération, les lectures doubles incohérentes et le refus
des mutations hors du helper root. Ce test ASan/UBSan utilise des clients factices
et n’appelle aucun setter natif.
