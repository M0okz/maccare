# Documentation publique du site

## Publication HTTPS 0.2.17 et synchronisation Outline — 9 novembre 2026

MacCare 0.2.17 (build 19) est publié sur GitHub. Les sources du site portent les
nouveaux liens, taille, SHA-256 et références de version des guides. Le catalogue
hybride est livré ; les guides Batterie et Confidentialité précisent les batteries
mobiles, l’accès Wi-Fi USB explicite et les alertes facultatives iPhone/iPad.
Les limites Watch et disponibilité restent explicites.

L’accès Homelab est rétabli et les dix fichiers HTML sont déployés sur le
conteneur existant. Leurs dix réponses HTTPS correspondent exactement aux
SHA-256 des sources `5e33750`. Conteneur sain, propriétaires et modes 0644
conservés ; CSS, images, scripts et configuration nginx inchangés. Les copies
temporaires de retour arrière sont supprimées après contrôle. Les pages Outline
concernées sont mises à jour puis relues, avec leur contenu et leur emplacement
préservés. [Clôture et preuves](release-0.2.17-completion.md).

## Publication HTTPS antérieure — référence 0.2.16


État vérifié le 9 novembre 2026 : **publié sur le site**
https://maccare.homeblack.fr/documentation/.
Le téléchargement reste MacCare 0.2.16 ; le catalogue hybride de mises à jour
reste **en développement, non livré dans cette version**. Aucune extension du
catalogue au désinstalleur ni nouvelle version de l’app n’est publiée ici.

## Contenu et portée

Le site disposait d’une visite produit et d’une FAQ, sans espace de documentation.
L’accueil, la navigation (y compris mobile) et le pied de page donnent maintenant
accès à un index et huit guides : premiers pas, applications, mises à jour,
nettoyage, performances, batterie, fichiers/stockage et confidentialité.
Les guides utilisent la version publique 0.2.16 comme référence ; les fonctions
à venir portent un statut explicite. Le sitemap inclut les neuf pages.

Le guide Applications explique l’inventaire direct des paquets installés,
la sélection du paquet et des données détectées, les données oubliées et les
limites de reconnaissance des résidus. Une app ne doit pas être dans le
catalogue de mises à jour pour apparaître dans le désinstalleur. Le guide
Mises à jour distingue les sources publiées (Homebrew, App Store, NetNewsWire)
du catalogue hybride en développement et de l’exception officielle ArtCraft.

**7 822 fiches n’équivalent pas à 7 822 applications reconnues** : variantes,
polices, paquets, métadonnées insuffisantes et éditions ambiguës empêchent cette
assimilation. Le chiffre est présenté avec sa date de relevé, pas comme une
promesse de couverture. Aucun nombre d’apps désinstallables n’est annoncé.

Les métadonnées Homebrew pourraient indiquer des chemins spécifiques de résidus.
Cette possibilité est documentée comme une piste future : elle n’est pas
implémentée. Des chemins de données personnelles, partagées, sensibles ou
étendus devraient être filtrés et l’identité de l’app confirmée. Les actions
Ruby, uninstall et zap ne sont jamais exécutées par l’intégration actuelle.

## Présentation et maintenance

Pages statiques sous `site/public/documentation/`, styles propres dans
`site/public/documentation.css`, palette et composants partagés avec le site.
Aucune dépendance, police externe, collecte ni script n’est ajouté aux guides.
Le contenu est consultable et navigable sans JavaScript. Navigation par liens
natifs, titres hiérarchisés, lien d’évitement et indication de la page active.
Les liens du téléchargement, sa version, sa taille et son SHA-256 sont conservés.
Le public ne reçoit ni les documents Outline privés ni les analyses historiques.

À chaque livraison, vérifier les références de version dans l’index, les guides
et le pied de page. Ne retirer le statut « en développement » du catalogue
qu’après une livraison réelle de cette fonction. Les changements de suppression
ne se déduisent jamais d’une amélioration de la détection des mises à jour.

## Vérifications réellement effectuées

- 10 pages HTML contrôlées (accueil et neuf pages de documentation), 206 liens
  ou ancres internes valides, un h1 par page, pas de doublon d’identifiant ni style
  en ligne.
- Playwright local : 30 combinaisons page/largeur, à 320, 390 et 1 440 pixels,
  sans débordement horizontal. Navigation accueil → guides → Applications →
  Mises à jour, lien d’évitement au clavier, navigation sans JavaScript et
  repli à 720 pixels vérifiés. Le repli ne remplace pas un essai du zoom navigateur.
- Captures desktop/mobile relues : index, détail Mises à jour et section Guides
  de l’accueil. Pas de campagne complète VoiceOver ou clavier, pseudo-localisation
  ou RTL revendiquée.
- Publication ciblée de 13 fichiers sur le conteneur existant `maccare-site`,
  `cloud-docker-01:/opt/stacks/maccare/html`. Les trois fichiers préexistants
  remplacés correspondaient exactement aux sources Git avant intervention.
  Copies de retour arrière temporaires ciblées, supprimées après contrôle.
- Les 13 réponses HTTPS correspondent aux SHA-256 des sources locales ;
  `/documentation/` répond 200. Conteneur sain, permissions 0644/0755 conservées,
  configuration nginx et politique CSP inchangées. Images, script et distribution
  de l’app préservés.

Preuves dans `build/public-documentation-qa/` : `links.json`, `browser.json`,
`manifest.json`, `https-validation.json`, captures et `live-browser.json`.
Le site est publié depuis l’état de travail local ; aucun push, merge ou tag
Git n’est réalisé par cette intervention. Les changements d’applications du
catalogue hybride restent distincts de cette publication documentaire.

Après publication, la navigation réelle accueil → documentation → Mises à jour
→ Applications et les libellés de portée ont été vérifiés au navigateur, sans
erreur JavaScript. Captures : `live-documentation.png` et `live-catalogue.png`.

Outline mis à jour puis relu : index et chapitres 04, 07, 08 et 11 ; contenu
préexistant et emplacement conservés. Preuve : `outline-validation.json`.

## Préparation de la prochaine release — 9 novembre 2026

À la demande de Gregory, le catalogue hybride, ses tests et la documentation
sont enregistrés dans Git sur `codex/apple-device-batteries`. Le site et ses
guides sont déjà publiés ; la fonction de l’application reste non livrée.
La fusion de cette branche et la publication d’une nouvelle version restent
à effectuer. Aucun changement de version ni remplacement de la copie quotidienne.
