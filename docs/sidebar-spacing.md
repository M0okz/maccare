# Barre latérale plus aérée — Dev du 8 novembre 2026

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
