# Reconnaître un build de développement

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
