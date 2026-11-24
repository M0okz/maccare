# Interactions de la carte Espace disque — Dev du 9 novembre 2026

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

Évolution locale non publiée sur `codex/helper-process-icons`, après MacCare
0.2.14 (16). Paquet `build/space-bubbles/MacCare.app`, Dev 0.2.14 (13).

## Survol et ouverture

Le survol était attaché à chaque bulle après son positionnement dans la carte :
la zone de suivi pouvait englober le cadre de placement, au-delà du cercle
visible, et plusieurs zones concurrentes pouvaient désigner la mauvaise bulle.

Un suivi continu unique utilise maintenant les coordonnées locales de la carte
et `BubbleHitTest` pour identifier le cercle visible sous le pointeur. Les coins
du cadre, ombres et espaces entre les bulles n’activent aucun dossier. Le chemin
de survol reste partagé avec la liste de gauche, qui conserve son défilement
vers l’élément correspondant. Seul un changement de bulle publie le nouveau
survol. Sortir de la carte, la redimensionner ou la quitter nettoie cet état.
Le survol est prioritaire sur la sélection pour le contour et la ligne active.
`SpaceModel` conserve aussi l’origine active (carte ou ligne précise) : une
sortie tardive de l’ancien emplacement ne peut pas effacer le nouveau survol,
y compris quand la liste et la carte représentent le même dossier.

Sur la carte, un clic simple sélectionne l’élément et affiche ses informations ;
un double-clic ouvre un dossier dans l’explorateur Espace disque. Les fichiers
restent sélectionnables sans être lancés. Les zones de clic suivent elles aussi
les cercles et la consigne visible indique le double-clic. Les infobulles des
bulles sont retirées ; les actions de la liste et du menu contextuel restent en place.

Les bulles restent des boutons natifs nommés. L’action d’accessibilité permet
d’ouvrir directement un dossier, sans imposer le double-clic de la souris.
Les états Survolé/Sélectionné sont exposés dans la carte et la liste. Aucun effet
de mouvement ou délai de survol n’est ajouté.

## Validation

La reproduction native sur le dossier temporaire Fixture/Alpha confirmait
qu’un clic simple ouvrait Alpha immédiatement. Les huit tests `SpaceExplorerTests`
couvrent maintenant les cercles visibles, bords, coins hors cercle, intervalles
vides, cohérence avec le placement, sélection sans ouverture et navigation
explicite, ainsi que les comportements d’exploration existants.
Ils couvrent aussi l’ordre croisé des entrées/sorties carte/liste et entre lignes.

Dans la Dev installée, un clic physique simulé au centre d’Alpha sélectionne
le dossier en conservant Fixture et ses trois éléments. Un double-clic sur
Beta ouvre Beta et son fichier `sample.bin`. Un clic sur le coin hors cercle
d’Alpha n’active aucun élément. L’emplacement Macintosh HD est ensuite restauré.
Le mouvement continu d’une souris physique et VoiceOver complet ne sont pas
validés par cette automatisation ; la détection du survol est couverte par les
tests de géométrie, distinctement des clics natifs vérifiés.

Preuves locales dans `build/space-bubbles-qa/` : `red.json`, `tests.log`,
`build.log`, `package.log`, `validation.json`. La validation native finale est
consignée dans ce dernier fichier.
Seule `/Applications/MacCare Dev.app` est actualisée ; la copie quotidienne est
préservée et aucune release n’est publiée pour cette correction.

## Évolution depuis la dernière analyse — développement du 24 novembre 2026

Dans Mes fichiers, « Explorer dans Espace disque » reprend le dossier choisi.
Espace disque reste aussi accessible dans la barre latérale. Après « Explorer »,
la présentation **Évolution** compare les sous-dossiers directs de l’emplacement
courant. La première mesure sert de référence. Une actualisation affiche les
variations par amplitude, avec les nouveaux dossiers et ceux qui ont disparu.
Cliquer sur un dossier encore présent ouvre sa carte. Revenir au parent réutilise
la mesure affichée. Dans Réglages → Fichiers et disque, Évolution peut aussi
être choisie comme présentation initiale.

Les écarts expriment les octets alloués aux sous-dossiers. Un fichier placé
directement dans l’emplacement exploré reste visible dans Carte et Liste.
Un renommage apparaît comme une disparition et une apparition. Si l’une des
deux lectures d’un sous-dossier est partielle, la ligne indique « Mesure
partielle ». Lorsque la liste du dossier parent elle-même est illisible ou
incomplète, MacCare invite à vérifier l’accès et conserve la référence précédente.

MacCare garde localement les deux dernières mesures de chacun des douze
emplacements récemment mesurés, dans son dossier Application Support, sous
`SpaceHistory-v1`. Chaque emplacement est identifié par le chemin, l’UUID du
volume et l’inode du dossier. Les fichiers d’historique contiennent les dates,
noms des sous-dossiers, tailles et indicateurs de lecture complète. Si le volume
ne fournit pas d’identifiant stable, Carte et Liste restent utilisables.
Les paquets Dev et de distribution disposent chacun de leur dossier d’historique.

Vérification en DEV sur la branche `codex/app-action-pills`, base `f2d2bc9`
(commit du lot 2). Après avoir quitté et relancé le paquet signé, la comparaison
a affiché +500 Mo, −8 Mo et un dossier partiellement lisible. Le clic sur la
première ligne a ouvert le bon dossier dans la carte. Les journaux, le paquet
et le relevé natif sont disponibles localement dans `build/space-history/`.
