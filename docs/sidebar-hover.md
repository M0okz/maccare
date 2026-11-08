# Survol des catégories — 6 novembre 2026

Disponible dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14). Les descriptions Dev ci-dessous restent un historique daté avec leurs limites de validation.

Évolution Dev du 8 novembre : rayon porté à 12 points, lignes plus aérées et
Mes outils placé dans le pied. [Disposition et contrôles](sidebar-spacing.md).
Le comportement de survol ci-dessous est conservé ; les dimensions du 6 novembre
restent un historique daté.

Évolution locale non publiée, branche `codex/tray-storage-battery-details`, après
`51e6b4d`. Paquet `build/sidebar-hover/MacCare.app`, installé dans
`/Applications/MacCare Dev.app` (Dev 0.2.10, build 12).

La barre latérale reprend la forme de sélection sur la rubrique survolée. La
rubrique active conserve son fond plus marqué. Le survol ne navigue pas : seul
le clic appelle la sélection de rubrique existante. Le même style s’applique à
la barre complète et à sa version compacte en icônes.

`SidebarRowStyle` et sa surface privée gèrent localement l’état `onHover`, en
remplaçant le cadre dessiné directement par `Sidebar.row`. Rayon 9 points et
bordure 0,5 point conservés ; fond blanc à 13 % pour la sélection, 8 % pour le
survol et 0 % au repos. Bordure à 8 % pour la sélection, 4 % pour le survol.
Une rubrique sélectionnée et survolée conserve le seul état sélectionné, sans
cumuler les fonds. Fondu ease-out de 120 ms limité au fond et à sa bordure,
désactivé avec Réduire les animations. Retour d’enfoncement existant conservé.
Le survol visuel est ignoré quand le contrôle est désactivé.

Les boutons natifs, leurs libellés, les aides, les badges d’activité et le trait
d’accessibilité sélectionné restent en place. Aucun changement de police, de
disposition, de raccourci, de moteur d’analyse ou de logique de navigation.

## Validation et limites

- Build Release arm64, packaging, signatures profondes strictes et correspondance
  entre paquet et copie Dev installée vérifiés ; `git diff --check` réussi.
- Rendu natif de la barre complète et du rail compact contrôlé, catégorie active
  visible ; clic Applications → Performances et état sélectionné vérifiés dans
  l’arbre natif. Retour Recommencer → Analyser également contrôlé.
- Le survol seul n’est pas déclaré validé en exécution : les déplacements et
  clics synthétiques disponibles dans l’outil de QA ne reproduisent pas
  fidèlement l’événement de survol. Son état, ses opacités et la limitation de
  mouvement sont vérifiés dans le code. Confirmation visuelle à la souris réelle
  encore nécessaire. Pas de campagne complète VoiceOver, clavier ou Réduire les
  animations ; aucune nouvelle suite de tests pour cette finition réversible.
- Copie quotidienne `/Applications/MacCare.app` conservée en 0.2.8 (10), exécutable
  inchangé. Lancement Dev avec `-battery.protection.resume NO`. Copie temporaire
  de retour arrière supprimée après vérification. Aucune publication.

Preuves locales : `build/sidebar-hover-qa/` (build, packaging, identification des
paquets et validation). L’app reste ouverte sur une introduction pour comparer
le survol à la sélection active.

## Publication 0.2.11 — 6 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.11 (build 13)](https://github.com/M0okz/maccare/releases/tag/v0.2.11), tag `v0.2.11` sur `b7e76f2`, après fusion de la PR #18 et suppression de la branche `codex/tray-storage-battery-details`. Ce statut remplace celui de développement non livré des notes précédentes. Le DMG téléchargé et le flux Sparkle ont été vérifiés : signatures, notarisation et Gatekeeper valides. Les limites de QA datées restent applicables, dont le survol seul à confirmer à la souris réelle. La copie quotidienne en 0.2.8 (10) est préservée ; la Dev installée reste identifiée 0.2.10 (12).

## Publication 0.2.14 — 8 novembre 2026

Ces changements sont publiés dans [MacCare 0.2.14 (build 16)](https://github.com/M0okz/maccare/releases/tag/v0.2.14), tag `v0.2.14` sur `6e6c22d13979f0821ec56f6f3ba57e383e14ab2b`, après fusion de la [PR #21](https://github.com/M0okz/maccare/pull/21). La branche `codex/battery-card-polish` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des passes Batterie et navigation ci-dessus ; les validations et leurs limites datées sont conservées.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42525327447) et les CI de branche, de PR et de fusion sont réussis. Le DMG public téléchargé est vérifié : signatures Developer ID des quatre exécutables arm64, tickets de notarisation app/DMG, Gatekeeper, versions du helper, licences et sources smartmontools. Les signatures Ed25519 du flux et du DMG sont validées avec la clé publique ; latest correspond à la release. DMG : 15928628 octets, SHA-256 `4b6e8060b9056975222acde00583f0ec10cb32b8843829f7eb7ef68020d9c9fd`. Le site public pointe vers ce paquet avec les mêmes taille et empreinte ; HTML identique aux sources, conteneur sain, copie temporaire supprimée.

Les rendus ont été contrôlés dans les Dev précédentes à 1436 × 784. Les formats courts, le rail compact, les actions de fenêtre après agrandissement des boutons, le 14 pouces physique et une campagne complète VoiceOver/clavier ne sont pas déclarés testés dans ces passes. Aucune installation pendant la publication : la copie quotidienne et la Dev restent inchangées (Dev 0.2.13, build local 6). L’application de distribution n’a pas été lancée. Preuves : `build/release-0.2.14-qa/`, `build/battery-card-qa/`, `build/battery-health-badge-qa/` et `build/sidebar-spacing-qa/`.
