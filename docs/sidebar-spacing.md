# Barre latérale plus aérée — Dev du 8 novembre 2026

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

## Retour à la taille native des commandes — Dev du 8 novembre 2026

À la demande de Gregory, l’agrandissement des boutons fermer/réduire/agrandir
est retiré en Dev. `WindowConfigurator` ne modifie plus leurs cadres, leurs
bounds ni leur espacement ; le coordinateur dédié est supprimé. AppKit retrouve
la maîtrise complète de leur taille, de leur forme et de leur placement natifs.
La barre latérale aérée, ses marges et Mes outils restent ceux de la passe validée.
La description de l’agrandissement publié dans la 0.2.14 ci-dessous reste historique.

Paquet `build/native-window-controls/MacCare.app`, Dev 0.2.14 (build local 9),
non publié, sur `codex/helper-process-icons`. Ce retour conserve aussi le correctif
local des icônes des helpers. Build/signatures et contrôle natif consignés dans
`build/native-window-controls-qa/`. Aucun nouveau test pour ce retrait visuel
réversible. Contrôle natif sur l’accueil à 1436 × 784 : pastilles circulaires
revenues à leur taille et espacement natifs, rôles fermer/réduire/plein écran
présents. UUID compilé/paquet/installé concordants et signatures strictes réussies.
La copie quotidienne conserve son empreinte ; sauvegarde temporaire Dev supprimée.
Pas de campagne complète VoiceOver/clavier, de test sur l’autre Mac ni d’exercice
des trois actions système dans cette passe.

Disponible dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14). Les descriptions Dev ci-dessous restent un historique daté avec leurs limites de validation.

Développement sur `codex/battery-card-polish`, non publié. La distribution
publique reste MacCare 0.2.13 (15). Les corrections Batterie précédentes sont
conservées sur cette même branche.

`Sidebar` garde les sept rubriques principales en haut, dans leur ordre actuel.
Les lignes passent de 44 à 48 points, séparées de 10 points au lieu de 2. La
réserve supérieure passe de 58 à 70 points. Dans la barre complète de 240 points,
la marge intérieure horizontale passe de 12 à 24 points et l’écart icône/libellé
de 11 à 16 points. Le rail compact reste large de 82 points, ses icônes centrées.

L’entrée tools devient **Mes outils** et quitte le groupe supérieur pour le
pied. Après retour de Gregory, sa marge inférieure est de 44 points, soit une
remontée de 24 points par rapport à la première passe. Le bouton de réduction/
développement du rail reste au-dessus. Le groupe du haut peut défiler si la
hauteur manque, sans emporter Mes outils. Les identifiants, routes, badges et
raccourcis ne changent pas. Le titre de la page reprend le même libellé.

`SidebarRowStyle` porte le rayon des fonds sélectionnés/survolés de 9 à 12 points.
Les blancs, couleurs, opacités et comportement de survol sont conservés. Les
mouvements existants respectent Réduire les animations.

Le coordinateur de `WindowConfigurator` ajuste seulement les trois boutons
natifs de la fenêtre principale à un cadre d’au moins 14 × 14 points, avec
8 points entre cadres. Il conserve le dessin natif à partir de ses dimensions
d’origine, le centre vertical et les commandes AppKit. Ils gardent leurs aides,
états et rôles d’accessibilité. Le plein écran reste géré par macOS. Réglages,
fenêtres de mesures et volet de barre des menus ne sont pas concernés.

| Before | After | Why |
| --- | --- | --- |
| Navigation serrée | Lignes de 48 points espacées de 10 points | Donner plus d’air aux catégories |
| Icônes proches du bord | Marge intérieure de 24 points, écart texte de 16 points | Reprendre l’alignement de la référence |
| Outils dans le groupe supérieur | Mes outils dans le pied, à 44 points du bas | Distinguer l’accès aux outils |
| Petites pastilles de fenêtre | Boutons natifs circulaires légèrement agrandis | Améliorer leur présence et leur cible |

## Validation et état

4 tests existants de navigation réussis : routes accessibles, outils conservés,
filtrage développeur et historique. Aucun nouveau test pour ces dimensions
réversibles. Build Release arm64 et paquet Dev 0.2.13 (build local 6) dans
`build/sidebar-spacing/MacCare.app`. Contrôles natifs et limites consignés dans
`build/sidebar-spacing-qa/`.

Installé uniquement dans `/Applications/MacCare Dev.app`, sans flux Sparkle et
lancé avec `-battery.protection.resume NO`. Signature profonde stricte et UUID
compilé/paquet/installé concordants. Rendu natif final à 1436 × 784 : catégories
plus espacées, marge bord/icône et écart texte augmentés, Mes outils en bas avec
sa remontée de 24 points et boutons natifs visibles. Les rôles natifs fermeture,
plein écran et réduction restent présents. La copie quotidienne garde son
empreinte ; la sauvegarde temporaire de la Dev est supprimée après vérification.

Limites : pas de campagne complète VoiceOver/clavier ni de test physique sur
le 14 pouces ; rail compact, fenêtre courte et actions fermer/réduire/agrandir/
plein écran non exercés dans cette passe. Les tentatives d’ouverture Mes outils
ont été interrompues par des interactions utilisateur ; le pied final a été
vérifié visuellement sans reprendre ces actions. Le survol reste vérifié dans le
code, sans campagne à la souris réelle. Les 4 tests portent sur les routes et
non sur la géométrie des boutons. Aucune publication.

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.
