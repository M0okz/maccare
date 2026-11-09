# Bilan Applications : catégories à examiner et aperçu des mises à jour

**Publié dans [MacCare 0.2.20 (build 22)](https://github.com/M0okz/maccare/releases/tag/v0.2.20) le 9 novembre 2026.**
Ce statut remplace les mentions de développement non livré des étapes ci-dessous.
Les validations datées et leurs limites sont conservées.


9 novembre 2026 — **proposition visuelle validée par Gregory ; préparation pour la prochaine release**.
Branche `codex/applications-insights`, base `22d72fab270e55320a008188c02963fffa83a000`.
Checkout isolé sous `build/worktrees/applications-insights`, pour préserver les
changements Batterie en cours dans le checkout principal. Aucune publication,
installation quotidienne, validation utilisateur, fusion ou push revendiqué.

## Bilan et présentation

La disposition suit la référence fournie : carte Mises à jour à gauche ; apps
peu utilisées puis catégories conditionnelles à droite. Données oubliées et
démarrage restent accessibles plus bas. Les couleurs et composants MacCare sont
conservés. Le contenu s’empile si la largeur est insuffisante.

Jusqu’à trois apps réellement concernées par une mise à jour sont tirées au hasard
à la fin de l’analyse. Elles sont dédupliquées par URL et doivent exister sur le
Mac. Ce tirage reste stable durant la consultation du bilan ; un nouveau scan
peut le renouveler. L’aperçu proposé évolue vers un mini Dock : trois icônes légèrement superposées,
l’icône centrale plus grande et au premier plan, la dernière fondue vers la
transparence. Un badge +N indique les autres résultats au-delà des icônes visibles. Avec moins de trois
apps reconnues, seules les icônes existantes sont affichées. Aucun compteur ou
résultat n’est inventé pour remplir l’aperçu. Les icônes sont décoratives pour
l’accessibilité, la liste Mises à jour conserve les noms et les actions.

## Applications peu utilisées — seuil choisi : 30 jours

Le choix initial proposé était 90 jours ; Gregory a retenu **30 jours**.
Une app est proposée seulement si :

- sa dernière ouverture Spotlight connue remonte à au moins 30 jours ;
- sa date d’arrivée à son emplacement courant est connue et remonte à au moins
  30 jours (délai de grâce pour les apps récentes ou déplacées) ;
- elle n’est pas ouverte lors du début du scan ;
- elle n’est pas déclarée agent `LSUIElement` ou `LSBackgroundOnly`.

Les dates futures et les dates inconnues ne deviennent jamais « jamais utilisée ».
Le détail montre la dernière ouverture enregistrée, la règle et le nombre d’apps
aux dates incomplètes. C’est un signal d’examen, pas une preuve d’inutilité.
Spotlight décrit les ouvertures via LaunchServices ; des usages directs en ligne
de commande ou en arrière-plan peuvent ne pas actualiser ces données.
Aucun historique privé d’usage ni collecte réseau n’est ajouté.

## Applications incompatibles

Le scan lit les architectures du binaire principal avec `/usr/bin/lipo -archs`
et les clés `LSMinimumSystemVersion`/`LSMinimumSystemVersionByArchitecture`.
Une architecture non prise en charge (par exemple uniquement 32 bits sur un
macOS récent) ou une version minimale trop récente constitue un résultat.
Une app Intel sur Apple Silicon n’est pas déclarée incompatible au seul motif
qu’elle peut nécessiter Rosetta. Une architecture ou un minimum inconnu reste
inconnu ; une route d’exécution à l’exigence inconnue ne suffit pas à déclarer
l’ensemble incompatible. La carte n’apparaît que si des blocages sont repérés.

Il ne s’agit pas d’un test de lancement : extensions, signatures, dépendances,
minimums encodés seulement dans les commandes Mach-O et bugs d’exécution peuvent
rester non détectés. Aucune app analysée n’est exécutée pour ce contrôle.
Les catégories d’apps conduisent à la revue de désinstallation existante, sans
désinstallation automatique.

## Installateurs

Réutilisation de la règle fermée embarquée `downloads.installers` et du moteur
existant : fichiers `.dmg` et `.pkg`, directement dans Téléchargements. Les ZIP
et téléchargements aux extensions partielles ne sont pas assimilés à des
installateurs. La taille réelle et le nombre sont affichés ; la carte est masquée
si la liste est vide. Une erreur de lecture est indiquée comme telle.

On ne prétend pas que les fichiers ont déjà servi ou ne sont plus utiles.
La vue présente leurs chemins, tailles et un accès Finder. La sélection est vide
au départ. Une confirmation précède la mise à la Corbeille uniquement ; le moteur
revérifie la règle, la portée et l’identité. Ce parcours n’introduit pas de
suppression permanente ni d’installation. Aucun fichier personnel n’est retiré
pendant la QA de cette évolution.

## Vérifications

16 tests ciblés réussis : seuil 30 jours et bornes, inconnues/futures, période de
grâce, processus/agents, Intel/Rosetta, 32 bits, minimum par architecture et route
inconnue, sélection vide, règle DMG/PKG et plan de retrait du moteur sur une fixture
possédée. Cette fixture est supprimée en fin de test. Les premiers essais sous
le dossier temporaire macOS étaient correctement refusés par le moteur à cause
d’un chemin symbolique ; le cas positif utilise ensuite un dossier possédé sans
lien sous le dossier personnel. Aucun garde de sûreté n’a été retiré.

Build Release arm64 et signature profonde stricte du paquet Dev réussis.
Parcours réel : 46 apps, 5 peu utilisées, 12 mises à jour, 5 installateurs totalisant
1,31 Go. Le détail d’utilisation affiche 12 apps aux dates incomplètes et la
règle de 30 jours. Les cinq cases des installateurs sont décochées ; l’action
Corbeille est désactivée tant que la sélection reste vide. Aucune incompatibilité
certaine n’est remontée sur ce Mac : le cas non vide est couvert par tests.
Pas de suppression personnelle, de campagne complète VoiceOver/clavier,
Intel, anciens macOS ou contrôle de capteurs/batterie pendant cette QA.

Sources Apple :
[Date de dernière utilisation](https://developer.apple.com/documentation/coreservices/kmditemlastuseddate),
[date d’ajout](https://developer.apple.com/documentation/coreservices/kmditemdateadded),
[clés LaunchServices](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html).

Composants : `ApplicationInsights.swift`, `ApplicationsInsightsModel.swift`,
`ApplicationsInsightsManager.swift`, `ApplicationUpdateIconPreview.swift`,
`ApplicationsInsightCard.swift`, bilan/modèle/détail Applications et `AppState`.
Preuves locales sous `build/` : tests, journaux de build et captures de QA.

Capture réelle de validation : `build/applications-insights-qa/overview.png`,
paquet `build/approval-preview/MacCare.app`. Copie quotidienne inchangée
(SHA-256 `78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`).
Outline synchronisé et relu : index et chapitres 07, 08 et 11.
Les réglages et la suppression n’ont pas été exercés sur des données personnelles.

## Bulles d’information des cartes — 9 novembre 2026

À la demande de Gregory, six sujets reçoivent un petit bouton « i » : mises à
jour, apps peu utilisées, incompatibilités, installateurs, données oubliées et
démarrage. La carte Incompatibles conserve son affichage conditionnel ; son aide
est présente dans le composant lorsqu’un résultat existe.

Dans le worktree géré actif, branche `codex/applications-insights-popovers`,
l’aperçu précédent est repris avec ses seules modifications Applications.
Le checkout précédent et ses captures sont préservés pour comparaison.
Cette évolution reste locale et non livrée, sans commit ni push.

`ApplicationCardInfoButton` affiche un symbole de 14 points dans une cible de
28 × 28 points. Un clic ouvre un popover natif ancré au bouton, avec un titre,
un résumé, trois critères et les limites. « En savoir plus… » ferme la bulle puis
ouvre le gestionnaire intégré correspondant. Échap ferme aussi le popover.
Le contenu est centralisé dans `ApplicationCardInformation` ; les seuils
proviennent de la politique réelle plutôt que d’une copie numérique indépendante.

Les libellés d’accessibilité nomment chaque sujet (« À propos : … »), les puces
sont décoratives et aucun effet animé n’est ajouté. Ouvrir une explication ne
modifie ni les critères de détection ni la sélection des fichiers.
Les mises à jour, la compatibilité et le calcul d’utilisation restent identiques
à l’aperçu précédent. Les dates Spotlight inconnues ne deviennent pas des preuves
d’inutilité ; Intel/Rosetta et la portée DMG/PKG sont explicités.

Vérification : compilation Release arm64 et signature stricte ; ouverture de
l’aide Peu utilisées, fermeture avec Échap et navigation depuis « En savoir plus »
vers le gestionnaire Mises à jour contrôlées dans l’interface native. La préférence
d’ancrage est ajustée sous les cartes hautes pour conserver une capture lisible.
Pas de nouveau test miroir pour cet ajout de présentation, ni de campagne
complète VoiceOver/clavier ou de suppression de données personnelles.

L’ancrage final est orienté sous les cartes hautes (Mises à jour, Peu utilisées)
et au-dessus des cartes plus basses (Incompatibles, Installateurs, Données
oubliées, Démarrage). La fermeture native avec Échap et les liens vers les
gestionnaires Mises à jour et Peu utilisées sont vérifiés. La carte Incompatibles
n’est pas présente sur ce Mac ; son texte et son intégration sont vérifiés dans
le code, sans campagne native non vide revendiquée.

Paquet final de cet ajout : `build/card-info/MacCare.app`. Contrôle natif des cinq
boutons visibles, aides Installateurs/Données oubliées/Démarrage, fermeture par
Échap, liens vers Mises à jour et Peu utilisées et ancrages haut/bas vérifiés.
Captures dans `build/applications-info-qa/overview.png` et `startup-popover.png`,
preuve dans `validation.json`. Build et signature stricte valides ; empreinte de
la copie quotidienne inchangée. Aucune publication ni approbation revendiquée.

## Aide Mises à jour simplifiée — 9 novembre 2026

À la demande de Gregory, seule l’aide du bloc Mises à jour devient sommaire :
« Retrouvez les nouvelles versions disponibles pour vos applications. » puis
« Aucune mise à jour n’est installée automatiquement. » Le lien En savoir plus
est conservé. La liste des sources, le tirage des icônes et les limites techniques
ne figurent plus dans cette bulle. Les autres sujets gardent leurs explications.
La zone des critères est masquée lorsqu’elle est vide, sans espacement résiduel.

Texte court vérifié dans le paquet `build/updates-info/MacCare.app` après build
Release et signature stricte. Capture : `build/applications-info-qa/updates-popover.png`.
La copie quotidienne conserve son empreinte ; pas de publication de ce changement.

Précision du texte Mises à jour : « MacCare consulte plusieurs sources pour
repérer les mises à jour de vos applications. » L’avertissement d’absence
d’installation automatique reste conservé. Le terme « simultanément » n’est
pas utilisé : UpdatesModel vérifie actuellement les sources successivement
dans une même analyse. Aucun changement du moteur de vérification.


## Vérification parallèle et nouvelle proposition d’icônes — 9 novembre 2026

Cette évolution remplace le fonctionnement successif décrit plus haut. Les
sources Catalogue, NetNewsWire/Sparkle, Homebrew, App Store et macOS sont lancées
en parallèle selon la portée du scan. Les résultats sont publiés dès qu’une
source termine, dans un ordre d’affichage stable. L’état final attend toutes les
sources ; une erreur conserve les résultats des autres. Les commandes bloquantes
restent hors du thread principal et des threads coopératifs Swift. Le contrôle
rapide du tableau de bord reste local et inchangé.

À l’intérieur du catalogue, Homebrew public et les sources GitHub officielles
correspondant aux apps installées sont également interrogés en parallèle, avec
au maximum quatre requêtes en cours dans ce fournisseur. Les sources officielles
gardent priorité même si elles échouent. La déduplication recalcule chaque aperçu
à partir des résultats bruts pour rester correcte quel que soit l’ordre d’arrivée.
L’aide courte peut désormais indiquer « plusieurs sources en parallèle ».
Aucun gain chiffré n’est revendiqué sans benchmark réseau reproductible.

La proposition visuelle conserve les icônes réelles tirées au hasard en fin de
scan : groupe compact, légères rotations latérales, icône centrale de 72 points,
latérales d’environ 60 points, dernier bord fondu et badge du nombre restant.
Aucune animation ajoutée. Le groupe reste décoratif pour l’accessibilité ; le
total et la liste détaillée restent accessibles. Cette proposition reste locale,
soumise à validation visuelle, sans commit, push ni installation quotidienne.

Vérifications : 31 tests ciblés exécutés, 30 réussis et 1 test réseau facultatif
ignoré. Les nouveaux tests utilisent des barrières explicites : tous les
fournisseurs démarrent avant toute réponse ; publication progressive ; dernier
résultat CLI supprimé même si le catalogue a déjà été masqué par le flux officiel ;
échec isolé ; requêtes catalogue/GitHub simultanées ; priorité officielle en erreur.
Build arm64 Release et paquet Dev signés. Premier parcours natif réel : 46 apps,
12 mises à jour, 5 apps peu utilisées et 5 installateurs. Copie quotidienne vérifiée
inchangée par SHA-256. Campagne VoiceOver complète non effectuée.

Paquet de validation : `build/parallel-dock-final/MacCare.app`.
Capture : `build/applications-info-qa/updates-dock-preview.png`.
Journaux : `build/parallel-dock-tests.log`, `build/parallel-dock-build-final.log`,
`build/parallel-dock-package-final.log`.


## Validation et préparation de l’intégration — 9 novembre 2026

Gregory a validé le mini Dock et demandé le commit puis le push de l’ensemble
sur la branche `codex/applications-insights-popovers` pour la prochaine release.
Le commit regroupe les catégories Applications, le seuil de 30 jours, les aides
« i », le mini Dock et la vérification parallèle des sources. Les mentions de
validation en attente et d’absence de commit ci-dessus décrivent les étapes
précédentes de cette même évolution.

La base d’intégration est `origin/main` après la livraison de MacCare 0.2.19
(`837c00f`). Une PR vers `main` prépare l’intégration ; aucune nouvelle version
ni installation quotidienne n’est publiée par cette opération. Le code validé
et les preuves de QA restent ceux détaillés dans la section précédente.


## Installation depuis MacCare — développement suivant la 0.2.20

Le gestionnaire reçoit désormais une action Mettre à jour qui exécute les mises à jour compatibles. Cette évolution reste non publiée ; elle remplace les liens seuls des étapes précédentes et ne change pas l’absence d’installation pendant une analyse. Voir [les mécanismes, vérifications et limites](application-update-installation.md).
