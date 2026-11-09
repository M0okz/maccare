# Historique partagé de l’activité du Mac

## État — 9 novembre 2026

**En développement, non livré** sur `codex/stable-metrics-history`, après la
publication de [MacCare 0.2.15 (17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15).
Cette évolution remplace le cache lié à la visibilité livré en 0.2.15.
La copie quotidienne n’est pas remplacée par la Dev.

## Continuité et cadence

`AppState` possède un seul `TrayMetricsStore`, partagé par l’accueil, le volet
et les fenêtres de détails. Il démarre avec l’application. Les vues visibles
signalent uniquement le besoin de relevés rapides ; leur fermeture ne remet ni
les compteurs ni les historiques à zéro.

- Vue d’activité visible : un relevé par seconde ; capteurs CPU/GPU et
  ventilateurs relus au maximum toutes les cinq secondes.
- Aucune vue d’activité visible : un relevé léger toutes les cinq secondes pour
  CPU, GPU, RAM et trafic de l’interface principale. Aucune nouvelle lecture
  SMC/HID de température ou de ventilateurs, ni interrogation CoreWLAN ; les
  dernières métadonnées de liaison et de capteurs sont conservées.
- Le changement de visibilité réveille la même boucle sans réamorcer les compteurs.
- Veille réelle : arrêt des lectures. Au réveil, les compteurs CPU/réseau prennent
  une nouvelle référence ; aucun volume ni échantillon n’est inventé pendant la veille.
- Les courbes relient les points réellement mesurés, y compris de part et d’autre
  d’une fermeture de vue ou d’une suspension. Cette liaison visuelle ne représente
  pas des mesures collectées pendant la veille. Un changement d’interface/adresse
  ou de carte GPU démarre une nouvelle série pour ne pas mélanger les appareils.
- Quitter complètement MacCare arrête le suivi et libère l’historique.

## Affichage stable et historique

Les chiffres CPU, GPU, RAM et réseau sont lissés avec une constante de cinq
secondes. Les nombres des cartes sont actualisés toutes les trois secondes ;
le détail garde sa cadence normale. Pression mémoire, température,
indisponibilité et identité de connexion sont traitées séparément. Les relevés
bruts et les alertes ne sont pas remplacés par les chiffres lissés.

Les courbes des cartes couvrent dix minutes. Les détails CPU, GPU, RAM et réseau
proposent dix minutes, trente minutes ou une heure, avec moyenne et pic.
Chaque groupe de cinq secondes conserve la moyenne des relevés et leur maximum
pour les statistiques : un pic court reste donc compté dans le maximum.
Le graphique représente les moyennes, à leurs heures réelles, sans étirement
artificiel au premier lancement.

L’échelle réseau monte par paliers, avec une marge au-dessus du pic. Elle ne
redescend qu’après une minute de demande nettement plus faible. La carte tient
compte de sa fenêtre de dix minutes ; le détail élargit l’échelle si son historique
plus long le nécessite. Le changement de connexion réinitialise cette échelle.

## Coût borné

CPU, GPU, RAM, réception et envoi conservent au maximum 721 points chacun :
3 605 points au total, soit environ 85 Kio de valeurs numériques, hors structures
et vues. Aucun fichier, base de données, préférence ni collecte par processus en
arrière-plan n’est ajouté. Le suivi léger utilise la boucle existante ; les
courbes se dessinent à l’arrivée des relevés sans animation de défilement continue.
Cela limite le coût sans prétendre qu’une collecte a un coût nul.

Composants : `TrayMetricHistory`, `TrayMetricsStore`, `TrayMetricsSampler`,
`TrayMetricsReadout`, `TrayHistoryChart`, `TrayHistoryDetail`, `HomeActivityCard`,
`TrayMetricDetail`, `TrayWiFiDetail` et cycle de vie `TrayPanelController`.

## Vérification de cette évolution

Les deux régressions initiales ont été reproduites : arrêt au dernier consommateur
et découpe du tracé après trois secondes. Les contrôles couvrent la boucle unique,
les cadences 1/5 secondes, l’absence de réinitialisation pendant la navigation,
la suspension/reprise, les volumes réels à cinq secondes, deux heures de données
synthétiques, les bornes mémoire, les moyennes/pics, le lissage CPU/GPU et les
paliers d’échelle réseau. Les résultats du paquet et du contrôle natif sont
consignés dans `build/stable-metrics-qa/`. La suite complète comporte 290 tests
XCTest et 247 tests Swift Testing, tous réussis. Le paquet Dev 0.2.15 (18), signé
Apple Development sans flux Sparkle, est installé dans `/Applications/MacCare Dev.app`.
Sa signature, son binaire et le processus lancé ont été contrôlés. La copie
quotidienne 0.2.8 (10), son empreinte et sa signature sont préservées.

Le contrôle visuel natif reste **en attente** : l’outil a constaté un Mac verrouillé,
avec déverrouillage automatique suspendu après une entrée physique. Le
déverrouillage manuel a été demandé ; aucun contrôle visuel réussi n’est revendiqué.
Les sélecteurs natifs gardent leurs libellés ; les graphiques exposent durée,
moyenne et pic sous forme textuelle. Le respect de Réduire les animations est
conservé. Le parcours VoiceOver et le clavier restent à vérifier en session native.

Aucune campagne matérielle de veille, de consommation énergétique prolongée,
de multi-écran ou de VoiceOver n’est déduite des tests automatisés.

## Archive : validation du cache initial livré en 0.2.15

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
