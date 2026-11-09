# Site et Outline — clôture de MacCare 0.2.17

9 novembre 2026. **Terminé et vérifié**, à la demande de Gregory après
rétablissement des accès Homelab. Release stable 0.2.17 (build 19), tag
`v0.2.17` sur `22d72fa`, sources du site `5e33750`.

## Site public

[Accueil](https://maccare.homeblack.fr/) et neuf pages de documentation mis à
jour pour la 0.2.17. Déploiement ciblé des dix fichiers HTML sur le conteneur
existant `maccare-site`, dans `cloud-docker-01:/opt/stacks/maccare/html`.
Les dix réponses HTTPS sont identiques aux SHA-256 des sources. Liens de DMG,
notes de version, taille et empreinte correspondent à la release publique :
16 049 174 octets, SHA-256
`f787279babc1d33b67fc236fa2b726d1be153294cb014d2bd2c9438d6b7b332f`.
Les guides Batterie, Mises à jour et Confidentialité conservent les limites de
fraîcheur Watch, d’alertes iPhone/iPad et de couverture du catalogue.

Le conteneur est sain, propriétaires root:root et modes 0644 conservés.
Aucun changement de nginx, CSS, images, scripts, droits ou redémarrage du
conteneur. Aucun nouveau contrôle visuel complet navigateur n’est revendiqué :
la vérification de cette reprise porte sur les réponses HTTPS exactes, les
fichiers et l’état du service.

Avant remplacement, les dix fichiers distants correspondaient exactement à
l’arbre Git `22d72fa`. La recherche des sauvegardes locales n’a pas confirmé une
sauvegarde horaire de ces fichiers ; les sources Git fournissent leur état
antérieur exact. Des copies temporaires ciblées ont été créées, puis supprimées
après contrôle HTTPS, empreintes et santé du conteneur. Aucun snapshot ou dump
supplémentaire global n’est créé. Aucun fichier de retour arrière de cette
intervention ne reste sur le VPS.

## Outline

L’index et les chapitres 02, 03, 04, 06, 07, 08 et 11 sont actualisés puis
relus via l’API. Chaque page affiche la livraison 0.2.17, distingue la release
publique des copies installées et conserve les validations datées précédentes.
Le texte préexistant et l’emplacement dans la collection sont vérifiés après
écriture. La normalisation de Markdown des listes (`-` vers `*`), des espaces,
d’Unicode et des échappements est prise en compte dans la comparaison, sans
supprimer les mots, valeurs ou liens.

| Page | Révision vérifiée |
| --- | ---: |
| [MacCare — Documentation du projet](https://outline.homeblack.fr/doc/maccare-documentation-du-projet-KB7heabtuj) | 198 |
| [02 — Fonctionnalités et interface](https://outline.homeblack.fr/doc/02-fonctionnalites-et-interface-djiT9TJpqe) | 127 |
| [04 — Architecture, composants et frontières de confiance](https://outline.homeblack.fr/doc/04-architecture-composants-et-frontieres-de-confiance-j3bSKQFWRy) | 119 |
| [06 — Batterie, CPU, RAM et réseau](https://outline.homeblack.fr/doc/06-batterie-cpu-ram-et-reseau-JavPjcqonj) | 78 |
| [07 — Outils secondaires et gestion des applications](https://outline.homeblack.fr/doc/07-outils-secondaires-et-gestion-des-applications-WQgqL2gCxY) | 18 |
| [08 — Développement, build local et tests](https://outline.homeblack.fr/doc/08-developpement-build-local-et-tests-tbm6e6K6tm) | 226 |
| [11 — Dépannage, validations et historique des décisions](https://outline.homeblack.fr/doc/11-depannage-validations-et-historique-des-decisions-XJWlBSapgi) | 246 |
| [03 — Réglages, profils et automatisation](https://outline.homeblack.fr/doc/03-reglages-profils-et-automatisation-eTnaWq120i) | 42 |

La synchronisation couvre le lecteur mobile, la configuration WirelessBuddyFlags
réellement testée, le dédoublonnage USB/réseau, les alertes facultatives de
batterie faible, le catalogue hybride, les sous-vues, les preuves de release
et le déploiement du site. Les limites restent explicites : dernier niveau
Watch sans date de mesure, aucune alerte Watch automatique, longue veille et
redémarrages non validés, absence initiale observée dans la Dev intégrée avant
réapparition après relance. Les nouvelles cartes Batterie du chantier parallèle
restent hors de la 0.2.17.

## Accès et traces

Le blocage initial était un délai TCP du bastion avant accès API, sans preuve
de refus Outline. Le helper Homelab retrouve maintenant le profil Bitwarden ;
l’accès VPS utilise le compte de service existant et sudo non interactif.
Aucun nouvel accès ou secret n’est créé, aucune permission de collection modifiée.
Les copies installées restent MacCare 0.2.8 (10) et MacCare Dev 0.2.15 (19) au
contrôle de cette reprise ; aucune installation n’est effectuée.

Preuves conservées dans `build/release-0.2.17-completion-qa/` :
`site-before.json`, `site-deploy.json`, `site-https-validation.json`,
`site-cleanup-validation.json`, `outline-validation.json` et les états du suivi.
Les copies complètes des pages et scripts temporaires sont supprimés après
validation. Le suivi Vikunja utilise **#100**, projet Homelab (4), vue Kanban
(16), avec clôture dans Done (75) après vérification du commit et du push.
