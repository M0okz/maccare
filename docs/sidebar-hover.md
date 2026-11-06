# Survol des catégories — 6 novembre 2026

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
