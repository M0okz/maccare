# Historique partagé de l’activité du Mac

## Historique persistant en développement — 26 novembre 2026

Branche locale `codex/persistent-metrics`, basée sur `3367999` (0.2.45). Cette évolution concerne la DEV.

Les détails Processeur, GPU, Mémoire et Réseau proposent 10 min, 30 min, 1 h, 24 h, 7 j et 30 j. Les cinq séries sont la charge CPU, la charge GPU, la part de RAM utilisée et les deux débits de l’interface principale. Les écrans courts retrouvent la dernière heure au démarrage. Une période longue charge les minutes déjà enregistrées de la seule série demandée. Les graphiques gardent les ruptures de session et de source. Le direct reprend avec de nouveaux compteurs. Les volumes transférés affichés sous les débits repartent à zéro pour la connexion de la nouvelle session.

`ActivityHistoryArchive` utilise le SQLite système depuis un acteur distinct de l’interface. Le fichier se trouve sous `~/Library/Application Support/MacCare Dev/Activity/history.sqlite` en DEV et sous `~/Library/Application Support/MacCare/Activity/history.sqlite` pour une construction de distribution. Chaque lot écrit en une transaction les groupes de 5 secondes de la dernière heure et les résumés par minute des 30 derniers jours. Les nouvelles lignes conservent la durée couverte, la somme des valeurs multipliées par leurs durées, le maximum et l’instant de ce maximum. Les dates sur disque sont des dates civiles. Le calcul d’un débit ou d’un volume en direct utilise le temps monotone. Le fichier enregistre une empreinte de la connexion et l’identifiant du GPU pour distinguer les sources.

MacCare écrit environ une fois par minute et vide le dernier lot lors d’une fermeture normale. Une interruption brutale peut perdre le lot en cours. Une erreur d’écriture conserve jusqu’à une heure de données pour la prochaine tentative. Les lignes expirées sont purgées à la réouverture et lors des écritures. La collecte s’arrête pendant la veille ou lorsque le processus quitte. Avec la barre des menus activée, la fermeture de la dernière fenêtre laisse le suivi léger en activité.

`HomeMetricsStore` publie les cartes de l’accueil toutes les cinq secondes. La première mesure CPU et les changements de pression mémoire, de GPU ou de connexion peuvent déclencher une mise à jour anticipée. Les relevés visibles et les détails conservent leur cadence d’une seconde. Une pointe entre deux dessins reste donc comptabilisée.

### Moyenne, interruptions et heure du pic

Chaque mesure valide représente l’intervalle monotone écoulé depuis la précédente mesure valide et continue de la même série. La moyenne additionne les valeurs multipliées par leurs durées, puis divise par la durée couverte. Deux minutes de même durée à 80 % puis 20 % donnent ainsi 50 %, que la collecte ait lieu chaque seconde ou toutes les cinq secondes. Une première lecture isolée peut fixer un pic. Sa durée est nulle jusqu’à ce que deux lectures établissent un intervalle.

Une lecture indisponible coupe la série concernée, même si les deux côtés de la coupure tombent dans la même tranche de cinq secondes ou dans la même minute archivée. Une interruption de collecte supérieure à quinze secondes, une reprise de session et un changement de source interrompent également la continuité. Le GPU, le CPU, la mémoire et les deux sens du trafic suivent chacun leurs propres interruptions.

Les détails donnent l’heure locale du pic à la seconde, avec la date pour les périodes longues ou un pic de la veille. À maximum égal, l’affichage retient la première occurrence datée disponible. Les lectures restent regroupées selon la résolution de l’archive. La minute partielle du début de fenêtre reste distincte des minutes suivantes pour empêcher qu’un pic antérieur à la période masque leurs pics.

Au premier accès, une transaction ajoute les colonnes `seconds`, `integral` et `peak_time` à `history`, puis fixe `PRAGMA user_version=1`. Le fichier et les anciennes lignes sont conservés. Pour les anciennes lignes, la durée estimée est plafonnée à la largeur de la tranche et à cinq secondes par lecture. Une moyenne incluant ces données porte le libellé « Moy. estimée ». Une ancienne tranche comptant une seule lecture permet de dater son pic. Pour un ancien maximum groupé sans occurrence connue, l’interface indique « Heure du pic inconnue ».

### Coût du détail CPU sur trente jours

La mesure locale utilise 43 200 lignes par série (216 000 lignes minute pour les cinq séries), plus les points récents de cinq secondes. Deux variantes du nouveau format ont affiché la même courbe via le code Swift optimisé de l’application, dans un `NSHostingView` de 330 × 154 points. Chaque mesure inclut la lecture de la période, le regroupement, les statistiques et le dessin de la carte. L’écriture du lot a lieu en dehors du chronométrage. Après le premier affichage, trois passages alternés de trente actualisations par variante donnent les médianes suivantes.

| Variante | Lecture et regroupement | Lecture et rendu |
| --- | ---: | ---: |
| Version précédente `dbbbf6a` | 14,6 ms | 17,4 ms |
| Moyenne temporelle et heure du pic, requête SQLite ordonnée par tranche puis par date | 18,2 ms | 21,1 ms |
| Même format, parcours de l’index et tri des tranches à plusieurs segments | 9,6 ms | 12,4 ms |

La version retenue lit les minutes via la clé primaire existante. Seules les lignes d’une même tranche comportant plusieurs segments sont triées en mémoire pour rétablir leur ordre chronologique. Le rafraîchissement des longues périodes suit les lots validés, environ une fois par minute. La comparaison porte sur une courbe d’une archive synthétique pleine, sur un Mac.

Dans le même processus DEV signé, le détail CPU est resté ouvert 65 secondes sur 10 min puis 65 secondes sur 30 j. Le processus entier a utilisé respectivement 6,4 % et 6,0 % d’un cœur, collecte et tableau des processus compris. Un seul passage par période donne un ordre de grandeur. Le détail 30 j a affiché le pic CPU de 100 % injecté le 24 novembre à 12:05:07 et l’a conservé après l’écriture du lot suivant, puis après fermeture et relance du paquet DEV.

La suite complète vérifie les moyennes après changement de cadence, les interruptions indépendantes, les pics aux limites de période, la migration de l’ancien fichier et la lecture après réouverture. Elle compte 433 XCTest réussis, 7 intégrations optionnelles ignorées et 295 tests Swift Testing réussis.

### Vérifications initiales du 26 novembre

La suite de l’application passe avec 427 XCTest réussis, 7 intégrations optionnelles ignorées et 295 tests Swift Testing réussis. Les six nouveaux tests couvrent notamment la reprise après échec d’écriture, les regroupements et les pics, l’expiration sur dates simulées, la restauration du store, les changements de source et la cadence des cartes.

Sur le paquet DEV signé, l’écriture périodique contenait 58 relevés CPU. La fermeture normale en a porté le total à 68, regroupés en 15 points. La relance a préservé ces points. Les sessions présentent un intervalle de 11,8 secondes entre leur dernière et leur première mesure. Le détail CPU ouvert sur 30 jours affichait une moyenne de 27 % et un pic de 79 % pour les données effectivement présentes. La période de trente jours complète a été vérifiée par dates simulées.

Sur ce Mac, l’accueil de deux paquets DEV optimisés et signés a été comparé dans l’ordre référence, modification, référence, modification. Après dix secondes d’amorçage, chaque lancement a fourni deux mesures de trente secondes avec la fenêtre active. Consommation du processus entier en pourcentage d’un cœur :

| Paquet | Quatre mesures | Médiane |
| --- | --- | --- |
| Référence `3367999` | 9,26 %, 4,86 %, 2,86 %, 2,83 % | 3,86 % |
| Historique persistant et nouvelle cadence | 1,83 %, 1,80 %, 1,83 %, 2,03 % | 1,83 % |

Ces observations couvrent deux minutes par paquet sur une seule machine. L’autonomie et la consommation avec trente jours de mesures réelles restent à évaluer.

## Version livrée le 9 novembre 2026

**Livré dans [MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16).** Branche de préparation `codex/stable-metrics-history`, désormais fusionnée et fermée.
Cette évolution remplace le cache lié à la visibilité livré en 0.2.15.
La copie quotidienne n’est pas remplacée par la Dev.

### Continuité et cadence

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

### Affichage stable et historique

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

### Coût borné

CPU, GPU, RAM, réception et envoi conservent au maximum 721 points chacun :
3 605 points au total, soit environ 85 Kio de valeurs numériques, hors structures
et vues. Aucun fichier, base de données, préférence ni collecte par processus en
arrière-plan n’est ajouté. Le suivi léger utilise la boucle existante ; les
courbes se dessinent à l’arrivée des relevés sans animation de défilement continue.
Cela limite le coût sans prétendre qu’une collecte a un coût nul.

Composants : `TrayMetricHistory`, `TrayMetricsStore`, `TrayMetricsSampler`,
`TrayMetricsReadout`, `TrayHistoryChart`, `TrayHistoryDetail`, `HomeActivityCard`,
`TrayMetricDetail`, `TrayWiFiDetail` et cycle de vie `TrayPanelController`.

### Vérification de cette évolution

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

Après déverrouillage manuel, le contrôle natif de la Dev 0.2.15 (18) est
**réussi** le 9 novembre. Les courbes CPU/GPU/réseau restent continues à l’accueil
après les allers-retours Applications/Accueil. Le détail CPU sur une heure
conserve le pic historique de 100 % (moyenne observée évoluant de 7 à 10 %),
y compris après fermeture du détail et du volet, passage dans Applications sans
métriques affichées, puis réouverture du volet. Les anciens points restent
visibles au lieu de recommencer la courbe.

Les détails GPU sur trente minutes, RAM et réseau sur une heure ont été ouverts.
Moyenne/pic, sélecteurs et disposition des deux cartes réseau sont visibles sans
débordement. Cette validation porte sur le changement d’échelle et l’historique
accumulé pendant la session, pas sur une collecte native complète d’une heure.
Les libellés de durée/moyenne/pic sont exposés dans l’arbre d’accessibilité ;
Échap ferme le détail surgissant puis le volet. Aucun parcours VoiceOver ou
clavier complet n’est revendiqué.

Observation courte de l’application entière, onglet Applications et volet fermé :
0,24 seconde CPU en 26,16 secondes, soit environ 0,92 % d’un cœur. Ce relevé `ps`
ne dispose pas de référence avant changement et n’isole pas le coût de la seule
collecte ; il ne prouve pas une consommation nulle. Preuve :
`build/stable-metrics-qa/background-observation.json`.

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
