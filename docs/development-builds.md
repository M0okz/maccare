# Reconnaître un build de développement

## Appareils jumelés — développement du 9 novembre 2026

**Non livré**, branche `codex/apple-device-batteries`. Nouveau lecteur mobile
natif signé séparément dans le paquet Dev. Les copies installées quotidienne
et Dev sont préservées ; le paquet de QA est préparé sous
`build/apple-device-batteries/MacCare.app`. Lecture USB iPhone/Watch vérifiée ;
Wi-Fi et consommation prolongée restent à tester sur les appareils physiques.
Voir [le fonctionnement et les commandes de validation](apple-device-batteries.md).

## Retrait des applications — Dev du 9 novembre 2026

**Fonctions livrées dans [MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16) ; validation locale Dev 0.2.15 (19).** Paquet `build/applications-fix/MacCare.app`, MacCare Dev 0.2.15 (19), installé et vérifié. Les clics sur les lignes, la présélection du paquet et des données et la mise à la corbeille de deux applications factices ont été contrôlés dans l’interface native ; 541 tests réussissent. La copie quotidienne est préservée.

Voir [le contrat, les tests et les limites](application-removal.md).

## Historique des métriques — Dev du 9 novembre 2026

**Fonctions livrées dans [MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16).** Ancienne branche de préparation `codex/stable-metrics-history`, fusionnée et fermée. Le paquet `build/stable-metrics/MacCare.app` porte l’identité MacCare Dev 0.2.15 (18), sans flux Sparkle. Le suivi reste léger hors visibilité (cinq secondes), sans nouveaux relevés de température/ventilateurs/CoreWLAN. Les graphiques partagent une heure bornée en RAM, gardent dix minutes dans les cartes et relient les points réels. La copie quotidienne `/Applications/MacCare.app` reste distincte. Dev installée, 537 tests réussis ; contrôle natif de la continuité, des détails et des sélecteurs réussi après déverrouillage manuel.

Voir [le fonctionnement, les vérifications et leurs limites](activity-metrics-cache.md).

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

## Bulles Espace disque — Dev du 9 novembre 2026

`build/space-bubbles/MacCare.app`, Dev 0.2.14 (13), actualise uniquement
`/Applications/MacCare Dev.app`. Survol limité aux cercles et synchronisé avec
la liste, infobulles retirées, clic simple pour sélectionner et double-clic
pour ouvrir un dossier. Voir [les interactions et validations](space-bubbles-interaction.md).

## Température GPU M1 — Dev du 9 novembre 2026

`build/gpu-temperature/MacCare.app`, Dev 0.2.14 (11), actualise seulement
`/Applications/MacCare Dev.app`. Repli SMC GPU M1 ajouté et testé sur pilotes
simulés ; chemin HID maintenu sur le M1 local. Le relevé réel du M1 Max distant
reste à confirmer. Voir [les preuves et limites](gpu-temperature-m1.md).

## Cache des mesures — Dev du 8 novembre 2026

`build/metrics-cache/MacCare.app` porte l’identité MacCare Dev 0.2.14 (10), pour
actualiser uniquement `/Applications/MacCare Dev.app`. Les derniers relevés et
les courbes survivent aux fermetures de vues, avec arrêt du suivi hors visibilité.
Voir [les tests, limites et preuves locales](activity-metrics-cache.md).
Évolution locale non publiée sur `codex/helper-process-icons` ; la distribution
publique reste 0.2.14 (16) et la copie quotidienne est préservée.

## App Store sans Homebrew — développement du 7 novembre 2026

Le paquet `build/bundled-mas/MacCare.app` embarque mas 7.0.0, signé avec
MacCare et ses licences. La source App Store utilise uniquement ce composant,
sans rechercher une installation Homebrew. L'action des résultats ouvre
l'App Store. Voir [le fonctionnement, le packaging et la validation](app-store-updates.md).
Évolution locale non publiée sur `codex/bundled-mas` ; la copie quotidienne et
les autres paquets Dev restent préservés.

Les paquets assemblés par `app/package.sh` affichent **MacCare Dev** dans la
fenêtre principale et comme nom d’application macOS. Ce repère reste visible
pendant la navigation, sous les boutons de la fenêtre : « Dev » seul lorsque la
barre latérale est réduite.

Le packaging écrit le booléen `MacCareDevelopmentBuild` dans `Info.plist`, avant
signature. Il est vrai par défaut et faux avec `MACCARE_DISTRIBUTION=1` : les
distributions conservent le nom **MacCare**, sans repère Dev. Le rôle ne dépend
pas de `DEBUG`, les builds locaux étant également optimisés en Release. Un
exécutable lancé sans métadonnées de paquet se présente comme un build Dev.

Ce libellé facilite l’identification ; il ne crée pas d’isolation entre les
préférences, les consentements ou le service privilégié. Le bundle ID reste
`org.maccare.app`. Toujours vérifier le chemin exact avant une intervention et
préserver la copie utilisateur dans `/Applications/MacCare.app` lors du
développement. Un ancien paquet conserve son ancien affichage jusqu’à sa
reconstruction ; aucune installation utilisateur n’est nécessaire pour tester
le nouveau repère.

## Volet compact — développement du 6 novembre 2026

Le paquet `build/tray-layout/MacCare.app` permet de vérifier le volet
compact et la présence dans le Dock à la fermeture/réouverture d’une fenêtre.
Il affiche MacCare Dev et ne remplace pas la copie dans Applications.
Voir [la disposition, les contrôles et les limites](menu-bar-panel.md).

Ce paquet inclut aussi la grille de stockage, la pression mémoire, la température
CPU et le réseau actif/IP/Mb/s. Pour sa QA, le lancement utilise
`-battery.protection.resume NO` et ne reprend pas la protection de charge.

La dernière passe ajoute un indice de santé explicable et l’en-tête RAM/stockage/
macOS/uptime, ainsi que la carte batterie enrichie et ses relevés en lecture seule.

La passe suivante simplifie l’en-tête (caractéristiques et uptime sur une ligne,
score chiffré réservé au détail), ajoute GPU et ventilateurs en lecture seule,
et configure jusqu’à quatre raccourcis dans Réglages → Menu. Le volet mesure
420 × 590 points au maximum. Plus et Quitter sont retirés de son pied ; ouvrir
MacCare et Réglages utilisent des icônes nommées. 53 tests ciblés et neuf
assertions C de décodage réussis ; rendu natif du volet et réglages blancs vérifiés.
État local non livré, `main` à `134b7bc` plus modifications de travail.

## Publication 0.2.10 — 6 novembre 2026

Les fonctions du volet sont désormais publiées dans MacCare 0.2.10 (build 12),
tag `v0.2.10` sur `e5dfb42`, après fusion de la PR #17 et suppression de la branche
`codex/compact-menu-bar`. Le paquet Dev ci-dessus reste une copie de QA locale,
distincte du DMG public signé et notarié. La copie quotidienne reste en 0.2.8 (10),
sans remplacement. Voir les preuves et limites dans `menu-bar-panel.md`.

## Correction des détails du volet — 6 novembre 2026

La branche `codex/tray-storage-battery-details` ajoute les popovers Stockage interne
et Batterie, après la publication 0.2.10. Le paquet `build/tray-details/MacCare.app`
porte toujours l’identité Dev 0.2.10 (12) et actualise `/Applications/MacCare Dev.app`.
Cette correction est locale, non publiée. Aucun remplacement de la copie quotidienne.
Voir `menu-bar-panel.md` pour les mesures, la navigation et les limites de validation.

## Bilan Nettoyage : retour à Analyser — 6 novembre 2026

Le paquet `build/cleaning-restart/MacCare.app` ajoute le retour à l’écran de
préparation depuis « Relancer l’analyse » du bilan Nettoyage, sans relance du moteur.
Il conserve les correctifs des détails Stockage/Batterie et met à jour la copie
`/Applications/MacCare Dev.app` (0.2.10, build 12, Apple Development). Ce travail
reste local et non publié, distinct de l’installation quotidienne préservée.

## Cohérence des boutons Recommencer — 6 novembre 2026

Le paquet `build/overview-restarts/MacCare.app` ajoute le retour à Analyser dans
Performances et Applications, avec le libellé Recommencer. Mes fichiers était
déjà conforme. Espace disque conserve explicitement son actualisation de la
mesure courante et son bouton Changer d’emplacement. Les quatre parcours ont
été vérifiés dans l’application, avec 37 tests ciblés réussis. La copie installée
`/Applications/MacCare Dev.app` est actualisée, toujours en Dev 0.2.10 (12), sans
publication ni remplacement de la copie quotidienne. Voir [les contrôles et
limites](analysis-restarts.md).

## Textes plus lumineux — 6 novembre 2026

Le paquet `build/text-contrast/MacCare.app` renforce les blancs du thème sombre,
retire l’opacité réduite des libellés du menu et éclaircit les textes secondaires
du volet. Il actualise `/Applications/MacCare Dev.app` (Dev 0.2.10, build 12),
sans publication. L’introduction et le bilan Applications, le gestionnaire blanc,
les réglages blancs et le volet réel ont été vérifiés. Build et signatures valides,
copie quotidienne inchangée. Voir [les couleurs, mesures et limites](text-contrast.md).

## Survol des catégories — 6 novembre 2026

Le paquet `build/sidebar-hover/MacCare.app` ajoute un fond arrondi au survol des
catégories, plus léger que la sélection active, sans navigation automatique.
Style partagé entre barre complète et rail compact, fondu de 120 ms désactivé
avec Réduire les animations. La copie Dev installée est actualisée (0.2.10, build
12), sans publication ni remplacement de la copie quotidienne. Build, signatures,
sélection et clics de navigation vérifiés ; confirmation du survol seul à la
souris réelle encore nécessaire. Voir [les contrôles et limites](sidebar-hover.md).

## Préparation de la version 0.2.11 — 6 novembre 2026

La prochaine publication réunit les corrections locales des détails Stockage et
Batterie, du retour à Analyser, des textes et du survol. La version source passe
à 0.2.11 ; le numéro de build sera attribué par le workflow de release. Les notes
de version conservent les limites de QA, dont le survol seul à la souris réelle.
Cette section décrit la préparation : aucune installation quotidienne effectuée.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).

Référence : [workflow de release réussi](https://github.com/M0okz/maccare/actions/runs/42265708515). Validation locale : `build/release-0.2.11-qa/`. Le DMG fait 10 233 711 octets, SHA-256 `8f40f18f1c22ce43ed8c89c917fb1e16f237921a2a77402ef8b9e2222f95dfb8`. Les suites locales comptent 251 XCTest et 226 Swift Testing, ainsi que 15 tests des outils de release. Frontière PowerUI sans appel natif d’écriture et contrôles négatifs Sparkle réussis ; CI Rust et macOS de la branche et de la PR vertes. Aucune installation de distribution effectuée dans cette livraison.

## Accueil enrichi — Dev du 6 novembre 2026

Le paquet `build/dashboard-cards/MacCare.app` intègre la maquette validée du bilan
et de la batterie : répartition réelle mémorisée, bouton Analyser, accessoires en
anneaux, chargeur en watts et processus énergivore. Activité du Mac est enrichi par six tuiles : CPU, GPU, mémoire, stockage, réseau
et ventilateurs, à la hauteur de la carte Batterie pour aligner la grille. Il actualise la copie Dev
installée (0.2.11, build local 1), sans publication ni remplacement de la copie quotidienne.
41 tests ciblés réussis ; rendu natif des six tuiles et des anneaux d’accessoires
vérifié. Voir [la disposition, les données et les limites](dashboard-cards.md).

## Accessoires compacts et stables — Dev du 6 novembre 2026

Le paquet `build/accessory-stability/MacCare.app` simplifie les accessoires en
pictogrammes entourés d’un anneau, sans section ni légende sous les icônes. Une
absence de relevé inférieure à 20 secondes ne retire plus immédiatement un
accessoire ; les niveaux récents expirent individuellement. Les emplacements
restent de dimensions constantes. 17 tests ciblés réussis, dont le cas auparavant
en échec. Le paquet conserve le numéro de build Dev local par défaut, 1, distinct
du build public 13 précédemment reporté par erreur pour la Dev. Installation
uniquement dans `/Applications/MacCare Dev.app`, copie quotidienne préservée.
Voir [les détails et limites](dashboard-cards.md).

## Disposition d’accueil validée — Dev

Le paquet `build/dashboard-approved/MacCare.app` intègre la deuxième maquette
validée : bilan sur toute la largeur, Batterie compacte et Santé du Mac empilées
à gauche, Activité en grille à droite. Le disque autonome en doublon est retiré.
Le résumé de santé réutilise le score et les mesures du volet, avec un accès au
détail des critères ; les informations de la maquette restent illustratives.
33 tests ciblés réussis. Disposition native, détail Santé et retour à Analyser
vérifiés. Paquet Dev 0.2.11 (build local 1), installé uniquement dans
`/Applications/MacCare Dev.app`, non publié. Voir [la disposition et les contrôles](dashboard-cards.md).

## Texte Santé aligné — Dev

Le paquet `build/health-alignment/MacCare.app` applique l’aperçu validé : tous les
textes du bloc Santé partagent une verticale, avec les icônes dans une marge dédiée.
La hauteur compacte et les informations sont conservées. Dev 0.2.11 (build local 1),
installation uniquement dans `/Applications/MacCare Dev.app`, sans publication ni
remplacement de la copie quotidienne. Voir [les contrôles](dashboard-cards.md).

## Outils natifs fichiers/disques — développement du 7 novembre 2026

Branche `codex/native-file-disk-tools`, après mas embarqué `226be66`. Paquet de QA
`build/native-tools-final/MacCare.app`, identifié MacCare Dev. Images PNG dans
Mes fichiers, diagnostic de santé dans Outils et sous-volet Stockage interne de
la barre des menus. Aucune nouvelle santé dans Espace disque. La copie quotidienne
et les autres Dev préexistantes ne sont pas remplacées. Voir
[le fonctionnement et les vérifications](native-file-disk-tools.md).

## Branche réunie et nouvelle Dev — 7 novembre 2026

Les commits mas embarqué et outils natifs ajoutés à `codex/dashboard-summary-cards`
sont vérifiés avec l’ensemble de l’accueil. Deux corrections de revue concernent
la taille PNG réellement traitée et l’échéance des commandes disque. Le paquet
`build/branch-integrated/MacCare.app` actualise `/Applications/MacCare Dev.app`
(0.2.11, build local 1). 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests
Python passent, ainsi que les contrôles PowerUI et Sparkle. Les nouveaux parcours
sont vérifiés dans la Dev installée et l’accueil est laissé ouvert. Aucun push
ni nouvelle release dans cette intervention ; copie quotidienne préservée.
Voir [la revue complète, les références et les limites](branch-integrated-review.md).

## Numéro de version actualisé — Dev du 7 novembre 2026

La version source passe à **0.2.12**, avec le build local **2**, dans
`app/Info.plist`. Le paquet `build/version-0.2.12/MacCare.app` actualise
`/Applications/MacCare Dev.app`. La fenêtre native À propos affiche bien
**Version 0.2.12 (2)** ; le descripteur du helper porte les mêmes numéros et le
canal development. Compilation Rust/Swift Release, 19 tests Python de packaging,
architecture arm64 des quatre exécutables et signatures strictes réussis.
Les suites fonctionnelles complètes de la revue précédente restent la référence :
cette intervention ne modifie que les métadonnées de version et leur documentation.
Copie quotidienne 0.2.8 (10) préservée, sans nouvelle publication. Preuves :
`build/version-0.2.12-qa/validation.json`, journaux de build, packaging et tests.

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.

## Échelle selon l’écran — Dev du 8 novembre 2026

Le paquet `build/display-layout/MacCare.app` actualise `/Applications/MacCare Dev.app`
en **0.2.13 (build local 3)**. La fenêtre principale adapte sa densité à l’espace
utilisable de son écran et réduit une ancienne fenêtre trop grande une seule
fois. Le rendu du Mac actuel reste à 100 %. 12 XCTest et 5 Swift Testing passent ;
build Release, signatures, rendu normal et aperçu compact natif vérifiés.
Pas de publication ou d’installation quotidienne. Le rendu sur l’autre Mac et
le format réduit cible restent à confirmer visuellement. Voir [la politique,
les contrôles et les limites](display-layout.md).

## Publication 0.2.13 — 8 novembre 2026

Cette adaptation est publiée dans [MacCare 0.2.13 (build 15)](https://github.com/M0okz/maccare/releases/tag/v0.2.13), tag `v0.2.13` sur `9a9dc5612dd9bf6b02c9438c3e721f2ca85efb2b`, après fusion de la [PR #20](https://github.com/M0okz/maccare/pull/20). La branche `codex/compact-interface` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des notes précédentes ; les validations datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42512588574) est réussi, comme les CI de branche, de PR et de fusion. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, notarisation et tickets app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; le flux latest correspond à la release. DMG : 15944980 octets, SHA-256 `0b790855ba2803ada5d33b1cea43c156bdc39dfebcc63719a6a9241c282e2a04`. Le site public propose ce paquet avec les mêmes taille et empreinte ; son HTML correspond aux sources et le conteneur est sain.

Le rendu sur le MacBook Pro 14 pouces en « Plus d’espace » reste à confirmer physiquement ; le format réduit cible a été testé par géométrie, l’aperçu compact étant observé dans une fenêtre plus grande. Pas de validation réelle de déplacement entre écrans ni de campagne complète d’accessibilité. Aucune installation quotidienne effectuée : la copie quotidienne et la Dev 0.2.13 (3) sont préservées. L’application de distribution n’a pas été lancée dans cette livraison. Preuves : `build/release-0.2.13-qa/`.

## Simplification Batterie — 8 novembre 2026, non publiée

Branche `codex/battery-card-polish`. Paquet `build/battery-card/MacCare.app`,
installé dans `/Applications/MacCare Dev.app`, version Dev 0.2.13 (build local 4),
sans flux de mise à jour et lancé avec `-battery.protection.resume NO`.
L’accueil réserve les anneaux aux accessoires et réduit le processus énergivore
à sa ligne icône/nom/valeur. MacCare et ses auxiliaires sont exclus de ce
classement. La lecture des processus passe de 5 à 15 secondes après amorçage ;
chargeur et accessoires restent à 5 secondes. Build Release arm64, signatures
strictes et 20 tests ciblés réussis. Rendu natif, alignement des cartes et accès
Batterie/retour accueil vérifiés ; les limites restent explicites dans
[les notes d’accueil](dashboard-cards.md). Aucun changement de distribution,
aucun remplacement de la copie quotidienne. Preuves : `build/battery-card-qa/`.

### Badge Santé — Dev 0.2.13 (build local 5)

Le paquet `build/battery-health-badge/MacCare.app` remplace le badge « Aucune
alerte » de l’accueil par « Santé : … % », issu du relevé réel. En absence de
valeur : « Santé : — ». La santé est également ajoutée au résumé accessible.
Le format conserve la carte compacte. Cette passe reste sur
`codex/battery-card-polish`, non publiée. Contrôles :
`build/battery-health-badge-qa/`, voir [les détails](dashboard-cards.md).

Le nombre réel de cycles remplace aussi le trait de séparation, et le nom de
l’application énergivore reprend le poids normal du texte.

## Barre latérale aérée — Dev 0.2.13 (build local 6)

Sur `codex/battery-card-polish`, la navigation gagne des espacements et une marge
intérieure plus larges. Mes outils est fixé dans le pied ; ce titre est repris
dans la page dédiée. Les boutons natifs de la fenêtre principale sont légèrement
agrandis, leurs commandes conservées. Paquet `build/sidebar-spacing/MacCare.app`,
non publié. 4 tests de navigation réussis. [Disposition et contrôles](sidebar-spacing.md) ;
preuves dans `build/sidebar-spacing-qa/`.

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.

## Icônes des helpers — Dev 0.2.14 (build local 8)

Branche `codex/helper-process-icons`, après la publication 0.2.14 (16). Paquet
`build/helper-icons/MacCare.app`, installé dans `/Applications/MacCare Dev.app`,
sans flux Sparkle, lancé avec `-battery.protection.resume NO`. Les helpers
reprennent l’icône de leur application englobante ; les services restent
représentés par le symbole générique. 18 tests ciblés, build et signatures
strictes réussis. Contrôle natif des helpers Claude/Codex et vérification du
vrai paquet Helium avec le même résolveur. [Détails et limites](process-icons.md).
Aucune publication ; copie quotidienne préservée. Preuves : `build/helper-icons-qa/`.

## Commandes de fenêtre natives — Dev 0.2.14 (build local 9)

Paquet `build/native-window-controls/MacCare.app` installé uniquement dans
`/Applications/MacCare Dev.app`, sans flux Sparkle et lancé avec
`-battery.protection.resume NO`. Sur demande de Gregory, le forçage de taille et
d’espacement des boutons fermer/réduire/agrandir est retiré. Le reste de la
navigation et le correctif des icônes des helpers sont conservés sur
`codex/helper-process-icons`. Ce retour visuel réversible ne reçoit pas de
nouveau test métier ; contrôle du build, des signatures et du rendu natif dans
`build/native-window-controls-qa/`. Aucune publication ; copie quotidienne préservée.


## Catalogue hybride Applications — 9 novembre 2026

**Développement local non livré.** La source Catalogue d’applications consulte le
catalogue public Homebrew sans installation de Homebrew ; ArtCraft Launcher
est suivi sur son dépôt GitHub officiel et NetNewsWire conserve son flux Sparkle.
Correspondances locales par identifiant et paquet, comparaison prudente des
versions, doublons regroupés et lien vers le téléchargement. Aucun inventaire
transmis ni installation automatique. Détails et limites :
[application-update-catalog.md](application-update-catalog.md).

Paquet signé `build/native-updates/MacCare.app`, MacCare Dev 0.2.16 (7).
29 tests ciblés et vérifications réseau réussis ; parcours natif Applications
validé avec douze résultats, dont onze du catalogue. ArtCraft non installé,
cas ancien simulé vérifié sur la vraie API. Copie quotidienne inchangée.
Preuves : `build/native-updates-validation.json`.
