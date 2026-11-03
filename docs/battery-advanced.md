# Batterie avancée — développement du 3 novembre 2026

Fonctionnalités introduites dans la version 0.2.0 du dépôt produit `maccare`.
Les disponibilités et limites de validation sont précisées ci-dessous ;
la présence d’une fonction dans le code ne certifie pas son contrôle matériel.
Le paquet de développement est `build/MacCare.app` ; la copie utilisateur
`/Applications/MacCare.app` reçoit les distributions signées par Sparkle.

## Fonctions

| Fonction | Comportement | Disponibilité |
| --- | --- | --- |
| Limite de charge | SMC : 50–100 % ; native : valeurs lues auprès de macOS | Contrôleur et firmware reconnus |
| Mode Voile | Plage de maintien configurable de 2 à 20 points | Contrôleur SMC compatible |
| Décharge volontaire | Utilise la batterie, câble branché, jusqu’à la limite ; annulable | Adaptateur reconnu, secteur et température fiables |
| Étalonnage | Pleine charge → 10 % → pleine charge → limite | Confirmation explicite ; aucune activation par défaut |
| Programmations | Une fois, quotidien, jours ouvrés, hebdomadaire, mensuel ; fuseau conservé | MacCare ouvert ; occurrence manquée au-delà de 10 min de retard |
| Raccourcis | Régler la limite, recharge ponctuelle, arrêt, décharge et étalonnage | Mêmes validations que l’interface ; confirmation de l’étalonnage |
| Profils | Préréglages et profils personnels, sans adaptation silencieuse | Profil refusé si ses réglages sont incompatibles |
| Historique | Mesures locales réelles, 30 jours et 10 000 entrées maximum | Aucun envoi réseau ; intervalle minimal sauf changement d’état |

Les quatre onglets sont Réglages, Cycles, Programmations et Historique.
Les métadonnées App Intents sont extraites pour Debug et Release lors du packaging.
Le fournisseur de raccourcis est enregistré au lancement via
`updateAppShortcutParameters()`.

La découverte dans Raccourcis **reste non validée sur le Mac de test** : macOS
renvoie « Bundle did not provide any metadata sources », bien que le paquet
contienne les quatre actions. Plusieurs copies partagent le même identifiant ;
un conflit de résolution est une hypothèse, pas une cause établie. La copie
quotidienne n’a pas été remplacée pour forcer ce contrôle. L’exécution directe
de l’intent et ses validations passent les tests ; cela ne prouve pas sa découverte
ni son exécution depuis Raccourcis.

## Contrôle et récupération

`MacCareBattery` contient les transitions pures. L’assistant authentifie l’appelant,
sérialise les commandes et possède un watchdog indépendant. Protocole local : 9.
Un UID et un UUID de session possèdent le bail de 90 secondes ; une lecture ne
le renouvelle pas. Après veille, une nouvelle prise de contact est nécessaire sous
15 secondes. Un redémarrage de fenêtre ne réactive pas une protection expirée.

Avant toute écriture, l’état initial est enregistré durablement et lié au Mac.
Le backend et l’adaptateur restent épinglés. La restauration rétablit l’adaptateur
avant la charge et conserve l’état natif initial. Une erreur d’écriture ne déclenche
jamais la découverte d’un autre mécanisme. Le journal v3 ajoute l’adaptateur et,
si nécessaire, la limite native compagnon ; les anciens journaux restent lisibles.

L’étalonnage attend 100 % **et l’arrêt de la charge** avant chaque décharge.
Chaque phase est bornée à 12 h, le cycle à 24 h. Mesures inconnues ou batterie
à 45 °C : interruption et restauration. Le retour au secteur admet 180 secondes :
le M1 de validation expose `PostDischargeWaitSeconds = 120`. Avec une cible
finale de 100 %, le cycle termine sans isoler de nouveau l’adaptateur.

Les programmations sont réclamées et synchronisées sur disque avant l’action.
Des verrous interprocessus empêchent deux instances de rejouer la même occurrence.
Une édition périmée ne réarme pas une tâche déjà réclamée.

## Compatibilité réellement constatée

Hôte physique : MacBookPro17,1, M1, macOS 27.0.1, firmware 20457.1.29.
Le diagnostic intégré UID 0 a lu les transports SMC 0/1, avec/sans ouverture
explicite. Dans les quatre cas :

- `bfF0`, `bfD0`, `bfE0`, `CH0J` : refus `kIOReturnNotPrivileged` (`0xe00002c1`).
- `CHTE`, `CH0B`, `CH0C`, `CH0I` : résultat `0x10084` (non disponible).
- `CHIE` : 1 octet, type `hex_`, valeur initiale 0.

Sur cet hôte, la voie native propose 80, 85, 90, 95 et 100 %.
**Les limites sous 80 % et le mode Voile ne sont pas activables avec ce firmware.**
Le refus est expliqué dans l’interface. Le maintien sur secteur n’est pas simulé
par une alternance permanente de recharge et de décharge. La décharge volontaire
reste une action distincte qui consomme effectivement la batterie.

Les Mac Apple Silicon sont détectés par capacité, sans liste M1–M6 figée.
La cible est macOS 13 ; chaque version et chaque matériel ne sont pas certifiés.
Un ancien macOS peut recevoir un firmware récent. Aucun essai physique M2 à M6
n’a été réalisé pendant cette intervention.

## Validation

- Build Release et contrôle du minimum macOS des objets Rust.
- Suite complète : 252 tests Swift réussis (167 XCTest et 85 Swift Testing),
  puis 135 tests Batterie/navigation après le dernier correctif (49 XCTest et
  86 Swift Testing). Les cycles complets,
  les erreurs, les transitions, les calendriers et la concurrence sont simulés.
- Tests C SMC sous ASan/UBSan, y compris restauration, rollback et diagnostic sans écriture.
- Tests Objective-C PowerUI simulés, sans appeler de setter système.
- M1 : activation à 80 %, recharge ponctuelle observée à environ 1,6 A, passage
  80 → 81 %, décharge volontaire, annulation et retour au secteur.
- M1 : confirmation et démarrage de l’étalonnage, puis annulation en phase 1.
  Aucun cycle réel jusqu’à 10 % n’a été imposé.
- M1 : interruption forcée du seul processus de développement pendant la décharge,
  récupération par l’assistant et conservation de la limite native 80 %.
- Interface : création/application/suppression d’un profil à 80 %, exécution réelle
  d’une programmation unique à 80 % et suppression de cette programmation.
  L’historique affiche les mesures réellement relevées, y compris l’essai 80 → 81 %.
- Fermeture du diagnostic par Échap vérifiée. VoiceOver et toutes les tailles
  de fenêtre ne sont pas déclarés validés.

La preuve locale non secrète est `build/battery-validation.json`.
La documentation Outline distingue ce développement de la version utilisateur 0.1.0.

## Sources primaires

- [AlDente — fonctionnalités](https://apphousekitchen.com/fr/aldente/fonctionnalites/)
- [AlDente — versions 1.39 et suivantes](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/releases)
- [AlDente — charge complète et étalonnage](https://apphousekitchen.com/macbook-charges-to-100-despite-charge-limit/)
- [batt — refus du firmware macOS 27](https://github.com/charlie0129/batt/issues/152)
- [batt — limites du mode adaptateur](https://github.com/charlie0129/batt/pull/154)
- [Battery Toolkit — alimentation](https://github.com/mhaeuser/Battery-Toolkit/blob/main/Libraries/SMCComm%2BPower.swift)

Le code historique public d’AlDente ne contient pas les fonctions Pro actuelles.
Aucune bibliothèque ou exécutable propriétaire d’AlDente n’est embarqué.
Les licences de la structure SMC déjà adaptée restent dans `THIRD_PARTY_NOTICES.md`.

## Correction du fond de la rubrique

Le fond violet provenait d’une régression de l’intégration des quatre onglets :
`BatteryView` utilisait `Theme.bg` à la place de `CategoryBackground(section: .battery)`.
La correction réutilise la palette verte existante pour tous les onglets. Le fond
reste décoratif, masqué des technologies d’assistance et sans interception des clics.
Aucune politique de charge ni définition de profil n’est modifiée.

Les profils Sur secteur (70 %, plage 60–70 %) et Usage mixte (80 %, plage 75–80 %)
restent indisponibles avec la voie native : le premier exige une limite sous 80 %,
les deux exigent une plage Voile. Une limite 80 % sans Voile et le profil Déplacement
100 % restent utilisables. Ces restrictions décrivent la méthode actuelle de MacCare.

Contrôles de ce correctif : compilation Release réussie, signature stricte du paquet
valide, fond vert constaté dans l’app lancée depuis `maccare/build/MacCare.app`,
protection native active à 80 %. La copie quotidienne conserve son empreinte.
Ce correctif visuel ne relance aucun cycle de batterie ; aucun nouveau test unitaire
qui reproduirait la ligne d’interface n’a été ajouté. VoiceOver n’a pas été retesté.
