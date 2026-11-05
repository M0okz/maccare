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
