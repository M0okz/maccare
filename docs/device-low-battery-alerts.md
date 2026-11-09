# Alertes de batterie faible des appareils

Développement du 9 novembre 2026, **non livré**, branche
`codex/device-battery-alerts`, basée sur `5f76971` de `codex/apple-device-wifi`.
Worktree : `build/worktrees/device-battery-alerts`. La correction de Gregory
remplace entièrement la demande initiale : **batterie faible uniquement**.
Aucun détecteur d’extinction ou d’indisponibilité n’est inclus.

## Réglage et présentation

**Réglages → Menu → Batterie faible des appareils** propose un interrupteur
persistant, désactivé par défaut, et un seuil réglable de 5 à 50 % par pas de
cinq. Aucun seuil n’ayant été imposé, la valeur initiale retenue est **20 %**.
Une bulle reprend le panneau AppKit commun aux alertes, avec nom de l’appareil,
niveau, heure de réception, **Ouvrir Batterie** et report d’une journée/semaine.
L’aperçu est fictif, sans lecture ni modification réelle d’appareil ou de rappel.

## Fraîcheur et appareils actuellement couverts

Les alertes automatiques exigent un **iPhone ou iPad lu directement**, un niveau
valide et une réception datée de moins de trois minutes (180 secondes incluses).
Un niveau absent, invalide, non daté, futur ou expiré ne devient jamais zéro.
L’historique visuel des cartes n’est pas une source d’alerte.

Le dernier niveau de Watch connu par l’iPhone ne possède pas actuellement une
date de mesure vérifiée. Son heure de réception par MacCare ne prouve pas la
fraîcheur de cette mesure : **aucune alerte Watch automatique à ce stade**.
Les accessoires macOS sans provenance temporelle fiable sont également exclus.
L’interface explique cette limite ; l’extension ne prétend pas surveiller tous
les périphériques ni connaître leur extinction ou leur disponibilité.

## Épisodes et consommation

- Une alerte par appareil et épisode. Elle n’est enregistrée qu’après une
  présentation réussie. Les identifiants hachés et dates de notification sont
  conservés localement, au plus 64 entrées ; noms et niveaux ne sont pas
  enregistrés dans ce registre de déduplication.
- Une nouvelle mesure directe et fraîche à **seuil + 5 points** réarme
  l’appareil. Au seuil de 20 %, il faut donc remonter à 25 %, puis redescendre
  à 20 % ou moins. Une valeur ancienne, une absence, une relance, un report
  ou une désactivation/réactivation ne suffisent pas à réarmer l’épisode.
- Les appareils ont des épisodes indépendants, sans suppression globale d’une
  journée après la première alerte. Le report explicite d’une journée/semaine
  reste commun à cette catégorie d’alertes.
- Une fois l’option activée, les lectures passent par le **même cache mobile**
  que les cartes et le volet : au plus une acquisition par minute, deux en
  économie d’énergie, cinq après absence/échec. Aucune nouvelle boucle,
  recherche Bluetooth permanente, élévation, configuration Wi-Fi ou jumelage.
- MacCare et sa barre des menus doivent rester ouverts, la configuration initiale
  doit être terminée et le Mac éveillé. Les requêtes déjà engagées restent
  bornées par le délai existant. Désactiver l’option arrête les nouvelles demandes
  du contrôleur d’alertes ; les vues ouvertes peuvent garder leur propre suivi.
- La bulle attend un moment où MacCare n’est pas au premier plan, sans grand
  volet, autre alerte ni analyse/nettoyage Smart Scan. Son affichage n’exécute
  aucune commande de charge ou action automatique sur l’appareil.

Composants : `DeviceLowBatteryPolicy`, `DeviceLowBatteryAlertView`,
`AdditionalAlertsController`, `AdditionalAlertKind`, `AdditionalAlertReminder`
et `AdditionalAlertSettingsView`. Le lecteur natif, ses barrières Wi-Fi et
`MobileDeviceBatteryStore` ne sont pas modifiés.

## Vérifications et limites

- Compilation Release arm64 de l’app, du helper et de la sonde via Swift tests.
  Le moteur lié est celui du checkout produit ; les sources et en-têtes du
  moteur sont identiques à la base de ce worktree.
- **41 tests Swift ciblés réussis**, dont dix nouveaux : seuil et option,
  âge/date future/niveau invalide, Watch indirecte, indépendance des appareils,
  déduplication après relance, récupération fraîche avec hystérésis,
  changement du seuil, absence de consommation d’un événement non affiché,
  reports et registre invalide. Les régressions mobiles, Wi-Fi et alertes
  existantes restent incluses.
- Hôte QA distinct `org.maccare.qa.device-battery-alert`, données fictives
  iPhone à 15 % : panneau observé en clair et sombre, texte, nom, pourcentage,
  heure, bouton et reports présents dans l’arbre natif. L’hôte temporaire a
  ensuite été fermé et supprimé. Aucun appareil réel n’a été interrogé ici.
- Empreintes des exécutables installés inchangées : quotidienne 0.2.8 (10),
  Dev 0.2.15 (19). Aucun paquet installé remplacé ou relancé pour cette QA.

Pas de validation complète des Settings dans le paquet de l’app, d’ancrage
réel sous l’icône, de parcours VoiceOver/clavier, de franchissement matériel
du seuil ni de mesure d’autonomie prolongée. Les limites et la reprise des
[essais Wi-Fi d’origine](apple-device-wifi.md) sont préservées ; leur correction
WirelessBuddyFlags reste non validée sur l’iPhone par cette intervention.

Preuves locales : `build/device-battery-validation/` dans ce worktree.
[Synchronisation Outline en attente](outline-sync-pending-device-battery.md).
