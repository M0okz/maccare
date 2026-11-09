# Cache des mesures d’activité — Dev du 8 novembre 2026

État local non publié sur `codex/helper-process-icons`, après la version publique
0.2.14 (16). Paquet Dev : `build/metrics-cache/MacCare.app`, 0.2.14 (10).

## Comportement

`AppState` possède un unique `TrayMetricsStore`, partagé par l’accueil, le volet
et les fenêtres de détails. Fermer le volet, changer d’onglet ou masquer la
fenêtre arrête le suivi lorsque le dernier consommateur disparaît, sans effacer
les dernières valeurs ni les courbes. La veille garde aussi ce cache en mémoire.
Il disparaît à la fermeture complète de l’application ; aucun fichier ni
préférence ne stocke ces mesures.

À la reprise, les compteurs CPU/réseau prennent une nouvelle référence pour ne
pas calculer une moyenne sur toute la pause. Les chiffres précédents restent
affichés pendant six relevés au maximum, uniquement pour amorcer ces compteurs ;
ils ne créent aucun point fictif ni volume réseau. Une lecture qui reste
indisponible finit donc par afficher son état habituel d’indisponibilité.

Les heures des relevés restent réelles : CPU/GPU couvrent 40 secondes, réseau
deux minutes. Les anciennes mesures expirent au prochain relevé, et une pause
de plus de trois secondes coupe la courbe au lieu de relier les deux périodes.
Une longue absence laisse donc progressivement place aux nouvelles mesures.
Une nouvelle interface, adresse ou carte GPU invalide l’historique concerné.

## Coût et limites

- Aucun nouveau timer, service, abonnement ou relevé en arrière-plan.
- Arrêt du suivi quand aucun consommateur n’est visible ; une fenêtre de détail
  visible continue à demander les relevés partagés.
- Maximum de 180 points par courbe CPU/GPU et 512 points réseau, soit 872 points.
  Les courbes se redessinent aux relevés, sans animation continue.
- Les caches de liaison et de capteurs gardent leur validité de 5 à 10 secondes
  lors de la navigation, sans forcer une relecture à chaque retour.
- Les chiffres réseau compacts appartiennent aussi au store : la cadence de
  trois secondes reste stable après recréation de la carte. Le détail réseau
  garde sa cadence normale.
- Les volumes réseau incluent seulement les intervalles observés. Aucun débit
  ni volume n’est estimé pendant une pause.

## Vérification

Le 9 novembre, 33 tests ciblés réussissent. La Dev 0.2.14 (10), signée Apple
Development sans flux de mise à jour, est installée et ouverte dans
`/Applications/MacCare Dev.app`. Dans l’interface native, l’historique CPU
compte 30 relevés après l’aller-retour Applications/Accueil, puis 25 après un
cycle de fermeture/réouverture du volet (16 au contrôle précédent). Les courbes
CPU/GPU/réseau restent présentes à l’accueil, avec les pauses visibles.

La copie quotidienne `/Applications/MacCare.app` reste en 0.2.8 (10), avec son
empreinte et sa signature préservées. La veille/reprise et l’absence de publication
de relevés à l’arrêt sont couvertes par les tests ; aucune campagne matérielle
de veille, multi-écran ou VoiceOver n’a été effectuée.

Le test de fermeture du dernier consommateur échouait avant correction : valeurs
CPU absentes et historiques vidés. Les tests ciblés couvrent désormais la
fermeture/réouverture, plusieurs consommateurs, veille/reprise, amorçage,
indisponibilité prolongée, bornes mémoire, expiration et coupure réelle des
tracés. Le suivi réel ne publie plus aucun relevé après son arrêt.

Preuves locales : `build/metrics-cache-qa/red.log`, `tests.log`, `build.log`,
`package.log` et `validation.json`. La validation native et la copie Dev installée
sont consignées dans ce dernier fichier ; les tests automatisés ne constituent
pas une mesure globale de consommation énergétique de l’application.
