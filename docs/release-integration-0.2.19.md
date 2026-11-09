# Livraison MacCare 0.2.19

9 novembre 2026. [Release](https://github.com/M0okz/maccare/releases/tag/v0.2.19),
build **21**, commit `c89d666c30680a2c23e4c061ea45b732ae3e4fd7`.
[Workflow de distribution](https://github.com/M0okz/maccare/actions/runs/42644912784) réussi. PR #25 puis #26 fusionnées
après réussite de leurs CI. Le tag v0.2.18 est conservé mais son workflow
42640631269 a été annulé avant publication, sans release publique.

## Périmètre livré

- Batterie : résumé réel, six cartes, palette verte et gestionnaires clairs
  intégrés avec Retour/Échap, navigation à gauche, détail et actions en bas.
- Assistant : réparation explicite d’un échec de lancement confirmé sans PID,
  validation Developer ID du remplaçant, conservation du journal root et
  contrôle du protocole. Un délai XPC seul ne suffit pas. Les Dev Apple
  Development n’interrogent plus le statut du service partagé.
- Accueil et volet : trois accessoires, téléphone et Watch réservés lorsqu’ils
  sont disponibles ; places libres et troisième cercle par niveau restant
  croissant, boîtier AirPods compris. Égalités stables et absence de doublon.
  Le détail garde tous les appareils dans le même ordre.
- Icônes : les sources IOPS conservent les catégories macOS, complétées par les
  usages HID et les noms usuels ; une souris renommée reste reconnaissable.

## Vérifications

333 XCTest (un test réseau facultatif ignoré), 259 Swift Testing, 19 tests Python
et signatures Sparkle réussis localement. Build Release arm64 et paquet Dev
signé vérifiés. CI Rust et App/DMG réussies pour le même arbre de sources.
La campagne matérielle précédente du 9 novembre sur ce correctif a vérifié
la pause à 55 % / 0 mA avec secteur tenu, la reprise à 2,7 A, la désactivation,
la restauration puis le rétablissement des réglages initiaux à 80 %.

Le DMG public (16112155 octets, SHA-256 `6430fda069ac0f16455b2e9d9707762b3b8224670d73c7dbf3818cd7f1fc3a4e`) et l’app embarquée
sont signés Developer ID, notariés et agrafés. Gatekeeper accepte l’app.
Architecture arm64, identité de distribution, version/build et configuration
d’assistant vérifiés dans l’image montée en lecture seule, sans lancement ni
installation. Signatures Ed25519 du flux et du DMG validées avec la clé publique
de la copie quotidienne ; le flux latest correspond à l’asset de cette release.

Dix pages publiques vérifiées en HTTPS par égalité de contenu et empreintes.
Conteneur maccare-site sain ; seul le HTML a changé, sans redémarrage ni changement
d’exposition. Ancien contenu couvert par Git et copie temporaire ciblée retirée
après contrôle. Huit pages Outline synchronisées et relues, contenu antérieur
et emplacement conservés. Le ticket Homelab #101 suit cette livraison.

## Limites

L’accueil Dev a été observé avec boîtier AirPods 81 % et écouteurs 82 %. Le volet
utilise la même sélection testée ; l’icône de statut n’était pas accessible à
l’automatisation native, donc son ouverture effective n’est pas revendiquée.
Pas de reconnexion physique de souris ni de campagne VoiceOver complète.
Les libellés, pourcentages et aides accessibles sont conservés.
Pas de nouvelle validation d’arrivée à 80 %, recharge complète à 100 %, décharge
volontaire, longue veille, redémarrage, autre Mac ou autre chargeur.
Les copies d’Applications restent inchangées ; la release ne les a pas installées.
Les captures web restent les anciennes captures explicitement signalées.
