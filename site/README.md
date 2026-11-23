# Site de MacCare

Page produit statique en français, publiée sur <https://maccare.homeblack.fr/>.
Elle ne contient ni dépendance, ni police externe, ni télémétrie, ni requête API.

## Prévisualiser

```sh
python3 -m http.server 4175 --directory site/public
```

## Contenu

- `public/` : la page, ses styles, son script et ses images.
- `deployment/` : conteneur nginx en lecture seule derrière Traefik.

Le mouvement suit les règles de [emilkowalski/skills](https://github.com/emilkowalski/skills) :
courbes fournies par le skill, `transform`, `opacity` et `clip-path` uniquement,
survol réservé aux pointeurs fins, aucune animation sur les actions au clavier
et variantes pour `prefers-reduced-motion`. La politique de sécurité interdit les
scripts et les styles en ligne : aucun attribut `style=` dans le HTML.

## À chaque release

Mettre à jour dans `public/index.html` :

- le numéro de version et les deux liens de téléchargement du DMG ;
- sa taille et son empreinte SHA-256, publiée à côté du DMG ;
- le lien vers les notes de version ;
- la description de la rubrique Batterie et ses limites, si elles changent.

## Captures

Les images de `public/assets/` sont de vraies captures de la fenêtre de MacCare.
Elles ne doivent montrer ni chemin, ni nom de dossier, ni nom de fichier personnel.
La rubrique Mes fichiers n’en a pas pour cette raison : son écran d’accueil affiche
le dossier personnel. Les captures actuelles viennent d’une préversion de la 0.2.2,
en définition standard (1291 × 728), et certains écrans ont changé depuis. Le site le
signale. Refaire ces captures depuis une version publiée, puis retirer la mention.

## Documentation publique

L’espace <https://maccare.homeblack.fr/documentation/> contient un index et huit
guides utilisateur sous `public/documentation/`. Ils partagent les styles du
site, complétés par `public/documentation.css`, sans script ni dépendance.
Les accès figurent dans la navigation, l’accueil et le pied de page.

Conserver les distinctions entre version publiée et développement : le catalogue
hybride est livré dans **MacCare 0.2.17**. Les guides sont déployés et vérifiés
en HTTPS, identiques aux sources de cette version.
Son nombre de fiches ne doit devenir ni un nombre d’apps reconnues garanti ni
un nombre d’apps désinstallables. Le désinstalleur ne dépend pas de ce catalogue.
Après une livraison, relire les versions de référence, statuts et liens dans tous
les guides, ainsi que `public/sitemap.xml`.

Validation et état de publication : [documentation publique](../docs/public-documentation.md).


Les guides ont pour référence **0.2.19** depuis le 9 novembre 2026 : refonte
Batterie, réparation d’assistant et priorités d’accessoires. Les références
à l’introduction du catalogue en 0.2.17 restent historiques.


Les guides prennent **0.2.20** comme référence depuis le 9 novembre 2026 : bilan Applications, seuil de 30 jours, incompatibilités, installateurs, vérification parallèle et rappel de mise à jour de MacCare. Les références aux introductions en 0.2.17 et 0.2.19 restent historiques.

Les guides prennent **0.2.22** comme référence depuis le 10 novembre 2026 : le bouton Mettre à jour lance les parcours compatibles depuis le gestionnaire Applications. Le site et ses dix pages HTML ont été relus en HTTPS, identiques aux sources. Les introductions historiques et l’avertissement sur les anciennes captures sont conservés.

Les guides prennent **0.2.23** comme référence depuis le 10 novembre 2026 : rappel de mise à jour stabilisé, architectures lues sans outils Xcode et procédure de remplacement depuis le DMG si une ancienne version quitte au lancement. Les dix HTML sont relus en HTTPS, identiques aux sources ; les introductions historiques et l’avertissement sur les anciennes captures restent conservés.


Les guides prennent **0.2.27** comme référence depuis le 14 novembre 2026 : onglet À propos, nouveautés et contour orange de disponibilité. Les dix HTML HTTPS correspondent aux sources, liens et ancres internes validés ; les introductions historiques et l’avertissement sur les anciennes captures restent conservés.


Les guides prennent **0.2.28** comme référence depuis le 15 novembre 2026 : stabilisation des commandes et optimisation de l’historique batterie. Les dix HTML sont vérifiés identiques aux sources en HTTPS ; les introductions historiques et les limites des anciennes captures sont conservées.


Les guides prennent **0.2.29** comme référence depuis le 15 novembre 2026 :
prise en charge en validation du seul M1 Max MacBookPro18,4, correction du message
de priorité Apple et mise à jour de l'assistant si proposée. Les dix HTML sont
identiques aux sources en HTTPS ; 216 liens/ancres internes sont vérifiés.
Les introductions historiques et limites matérielles restent explicites.


Les guides prennent **0.2.30** comme référence depuis le 22 novembre 2026 :
état Apple actualisable avant activation et diagnostic de jauge en lecture seule.
Les dix HTML sont déployés et relus en HTTPS, identiques aux sources ; 216 liens
et ancres sont validés. Le M1 Max reste explicitement en validation matérielle.

## Publication 0.2.31 — 23 novembre 2026

La page de téléchargement et les neuf pages de documentation décrivent la version publique 0.2.31 (build 33). [Contrôles du site et de la distribution](../docs/release-integration-0.2.31.md).

## Publication 0.2.32 — 23 novembre 2026

Les dix pages publiques prennent la 0.2.32 comme référence. Les icônes du site et le guide de prise en main reprennent Veille Améthyste. [Contrôles HTTPS et preuves de distribution](../docs/release-integration-0.2.32.md).

## Publication 0.2.33 — 23 novembre 2026

Le site propose la 0.2.33 et le guide de prise en main décrit la densité adaptative de l’accueil. [Contrôles de publication](../docs/release-integration-0.2.33.md).

## Publication 0.2.34 — 23 novembre 2026

Le site propose la 0.2.34. Le guide de prise en main présente la taille minimale de la fenêtre et la fiche des processus. [Contrôles de publication](../docs/release-integration-0.2.34.md).
