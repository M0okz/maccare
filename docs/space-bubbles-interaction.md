# Interactions de la carte Espace disque — Dev du 9 novembre 2026

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
