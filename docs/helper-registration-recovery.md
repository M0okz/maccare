# Réparation d’un assistant enregistré qui ne démarre plus

## Livraison 0.2.19 — 9 novembre 2026

Publié dans [MacCare 0.2.19 (build 21)](https://github.com/M0okz/maccare/releases/tag/v0.2.19),
tag sur `c89d666c30680a2c23e4c061ea45b732ae3e4fd7`, [workflow réussi](https://github.com/M0okz/maccare/actions/runs/42644912784).
Ce statut remplace les mentions de développement non livré des notes datées
ci-dessous. Les validations et leurs limites sont conservées. La publication
ne remplace pas les copies installées. Voir [le bilan de livraison](release-integration-0.2.19.md).

9 novembre 2026 — **développement non livré**, branche `codex/battery-cards`,
base produit `ddc711d`. L’interface Batterie par blocs a été validée par Gregory.
La correction suivante concerne le service système partagé et sa signature.

## Incident reproduit

La Dev affiche « assistant indisponible : délai de réponse dépassé » alors que
`SMAppService.status` vaut enabled. `launchctl print system/org.maccare.helper`
montre un ancien descripteur de distribution 0.2.2 (4), aucun PID, un état
`spawn failed` et la sortie `78: EX_CONFIG`. Les journaux smd précisent
`Invalid or missing Program/ProgramArguments`. Le service est encore enregistré,
mais n’est pas exécutable depuis son association de paquet courante.

Les copies partageant `org.maccare.app` font alterner l’association du paquet
parent dans Background Task Management. Après réenregistrement, le descripteur
exige toujours une validation Developer ID (catégorie 6) ; le helper d’un paquet
Apple Development est arrêté avec `OS_REASON_CODESIGNING`. Sa signature locale
valide ne prouve donc pas qu’il peut être lancé comme service privilégié.

Le SDK macOS installé (`ServiceManagement/SMAppService.h`) précise qu’un
exécutable/plist modifié doit être réenregistré et recommande de retirer
l’enregistrement précédent avant de le recréer.

## Correction

- `HelperLaunchFailure` accepte exclusivement le service exact, son exécutable
  embarqué, l’option de récupération chargée, l’absence de PID et l’échec de
  configuration observé. Une sortie inconnue, un processus présent ou un simple
  délai XPC ne suffisent pas.
- Le remplacement embarqué est vérifié avant tout retrait : plist de récupération
  et signature Developer ID de l’équipe MacCare, sans modifier les exigences XPC.
- `HelperServiceUpdater.repairFailedRegistration()` est une action explicite
  distincte de la mise à jour normale. Elle confirme deux fois l’échec, retire
  l’enregistrement et vérifie le protocole du remplaçant. Le journal root reste
  présent ; le helper récupère ce journal avant d’accepter de nouvelles commandes.
- Les mises à jour d’un assistant joignable conservent leur restauration préalable.
  Les échecs d’autorisation/signature ne sont pas masqués et aucune activation de
  protection ne fait partie de la réparation.
- La vue Protection propose « Réparer l’assistant système… » lorsque le service
  enregistré ne répond pas. Les états changés et les erreurs restent visibles.
- `HelperClient.status` évite d’interroger ce service depuis un paquet qui n’a
  pas de helper Developer ID compatible. Les Dev Apple Development ne doivent
  pas modifier passivement cette association par des appels de statut du daemon.
- `MACCARE_DEVELOPER_ID=1` active la signature Developer ID et le runtime durci
  dans `app/package.sh`, indépendamment de `MACCARE_DISTRIBUTION`. Le paquet
  conserve `MacCareDevelopmentBuild=true`, son nom natif MacCare Dev et son
  descripteur d’assistant de développement.

La séparation complète des identifiants des différentes copies n’est pas réalisée.
La réparation d’enregistrement est effectuée avec une seule copie active ;
les anciennes Dev Apple Development ont été fermées. La copie quotidienne est
fermée temporairement pour éviter de déplacer l’association pendant l’opération.
Les paquets d’Applications ne sont ni remplacés ni re-signés.

## Vérifications et limites

Le scénario de réparation a d’abord échoué dans les tests de régression, puis
les tests du cycle de service, du parseur et du modèle passent. Journaux sous
`build/helper-recovery-qa/` ; le contrôle local `check-service.py` est passé de
`ASSISTANT_UNAVAILABLE` à `ASSISTANT_RUNNING`. La Dev répond au protocole 10,
affiche Protection désactivée sans erreur et propose les commandes de charge.

Paquet signé pour les contrôles :
`build/helper-recovery-developer-id/MacCare.app`. Le service système démarre en
root à partir du helper Developer ID de cette Dev. La signature profonde stricte
et 19 tests Python de packaging passent. La relance de la Dev conserve la
communication avec le service.

La notarisation de ce nouveau paquet local n’est pas revendiquée : aucun profil
local trouvé, identifiants `MACCARE_NOTARY_KEY_P8`, `MACCARE_NOTARY_KEY_ID` et
`MACCARE_NOTARY_ISSUER_ID` absents de l’environnement du projet ; le repli
Bitwarden prescrit échoue avant accès documentaire confirmé. La signature
Developer ID et l’acceptation effective du service sur ce Mac sont vérifiées.
Ce paquet n’est ni publié ni présenté comme une release distribuable notariée.

### Contrôle matériel du 9 novembre

79 tests Swift ciblés réussis (5 XCTest et 74 Swift Testing), puis 19 tests Python
de packaging. La version finale ajoute aussi le filtre de signature Developer ID
avant les appels de statut et d’enregistrement. Le paquet final reste natif
MacCare Dev, avec runtime durci ; aucune exigence de signature n’est abaissée.

Le réenregistrement a d’abord été refusé avec « Operation not permitted » alors
que la copie quotidienne continuait de déplacer l’association du paquet parent.
Après sa fermeture temporaire, l’activation explicite depuis la Dev Developer ID
a réussi. Le helper root est lancé en développement 0.2.17 (8), protocole 10.

Avec le chargeur 65 W branché par Gregory, une pause thermique est provoquée
uniquement en abaissant temporairement le seuil à 30 °C, sans échauffer le Mac.
MacCare conserve sa limite configurée de 80 % et fait enregistrer un maintien à
55 % pendant cette pause :

- arrêt physique observé à 55 % : `IsCharging=false`, `InstantAmperage=0`,
  secteur présent et capable d’alimenter le Mac ;
- seuil rétabli à 31 °C et protection thermique désactivée, conformément aux
  réglages initiaux : limite 80 enregistrée, reprise mesurée à 2 729 mA,
  secteur toujours présent ;
- désactivation explicite : restauration terminée, état « Protection désactivée »
  et limite native initiale de 80 % rétablie ;
- protection réactivée à 80 %, comme l’intention persistante présente avant le
  contrôle. La configuration initiale (80 %, thermique désactivée, seuil 31 °C)
  et la préférence de reprise sont comparées et identiques.

La copie quotidienne `/Applications/MacCare.app` est rouverte, relit correctement
« Charge autorisée jusqu’à 80 % » puis retrouve sa vue Espace disque précédente.
La Dev finale reste au premier plan sur Protection et possède la session active.
Une seule session pilote la charge ; la copie quotidienne lit son état partagé.
Les empreintes des exécutables des deux copies d’Applications sont inchangées.
La copie temporaire de préférences et le paquet Apple Development d’essai raté
sont supprimés après comparaison. Le paquet fonctionnel et les preuves restent
sous `build/helper-recovery-developer-id/` et `build/helper-recovery-qa/`.

Cette campagne ne revendique pas une arrivée physique à la limite de 80 %, une
recharge complète à 100 %, une décharge volontaire, un cycle veille/redémarrage,
les autres Mac/chargeurs ou une campagne VoiceOver complète.
L’accès Outline reste en attente dans la note dédiée.
