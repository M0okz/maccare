# Rappel de mise à jour de MacCare

**Livré dans [MacCare 0.2.27 (build 29)](https://github.com/M0okz/maccare/releases/tag/v0.2.27), le 14 novembre 2026.** Le nouvel onglet À propos remplace le rappel jaune. Ce statut remplace les mentions de développement non livré de cette évolution ; les validations datées restent conservées. [Publication et limites](release-integration-0.2.27.md).

## À propos — 14 novembre 2026, en développement

État local sur `codex/about-updates`, base `ea8305a` de `origin/main`.
Cette évolution n’est ni publiée ni installée dans `/Applications/MacCare.app`.

Le bouton jaune de la barre native est supprimé. Une entrée permanente **À propos**
est placée juste sous **Mes outils**, en bas de la navigation. Son contour orange,
son symbole de téléchargement et sa valeur accessible « Mise à jour disponible »
signalent une version détectée par Sparkle. Le contour reste visible même si
À propos est sélectionné ; le symbole reste présent dans la navigation réduite.
Le menu macOS **À propos de MacCare** ouvre aussi cette rubrique.

La page affiche l’icône du paquet, sa version, une carte de mise à jour et les
liens publics du site, de la documentation et du code source, avec la licence MIT.
Les nouveautés proviennent de `SUAppcastItem.itemDescription` du flux déjà reçu
par Sparkle : aucun appel GitHub supplémentaire, téléchargement parallèle ou
exécution de HTML. Le Markdown en ligne est rendu en texte natif sélectionnable ;
les paragraphes et retours à la ligne sont conservés. Sans notes intégrées, ou en
présence de HTML, un lien vers les notes de version reste disponible.

**Télécharger la mise à jour…** ramène au panneau Sparkle, qui conserve les étapes
de téléchargement et d’installation. Le bouton est désactivé si le contrôleur est
occupé. Sans version détectée, la page propose **Rechercher les mises à jour…** ;
elle ne prétend pas que l’application est à jour lorsqu’aucune recherche n’a abouti.
Les builds sans configuration Sparkle affichent leur motif d’indisponibilité.
Les réglages de recherche automatique, notifications, signatures et mises à jour
critiques restent ceux du contrôleur existant. À la fin de sa session, les notes
et l’indicateur sont retirés selon le choix ou l’erreur gérés par Sparkle.

Composants : `AboutView`, `AboutReleaseNotesView`, `AboutSidebarButton`, `AppUpdater`,
`NavigationSection`, `Shell`, `CategoryPalette`, `DesignSystem` et `MacCareApp`.
Les anciens composants `AppUpdateAvailabilityButton` et
`AppUpdateAvailabilityToolbar` sont retirés. La sonde graphique utilisée par CI
compile maintenant les vues À propos et l’absence de rappel dans la barre native.

Validations du 14 novembre :

- Build Release arm64 réussi, paquet Dev signé et signature vérifiée dans
  `build/about-preview/MacCare.app` ; non lancé et non installé.
- 14 XCTest ciblés de navigation et de configuration/notification de mise à jour,
  sans échec ; couverture de la route À propos et de sa position après Mes outils.
- Quatre lancements de la sonde isolée, 640 alternances de disponibilité, sans
  exception ; aucune barre d’outils n’est désormais nécessaire dans cette sonde.
- Captures natives à 1200 × 800, 1200 × 720 et 860 × 620 avec et sans mise à jour,
  inspectées dans `build/about-qa/`. Les données de version sont simulées et le
  paquet de sonde utilise une icône générique ; aucun téléchargement ni accès
  batterie n’est lancé. Les fenêtres étroites utilisent le défilement de la page.
- La version quotidienne reste ouverte et n’est ni remplacée ni re-signée.

Limites : pas d’installation réelle d’une mise à jour dans cette campagne,
ni de campagne VoiceOver complète, ni d’exécution sur macOS 13–15.
La synchronisation de la documentation interne est suivie séparément.

### Aperçu interactif de disponibilité

Le paquet signé MacCare Dev peut être lancé avec `--preview-available-update`.
`AppUpdatePreview` exige à la fois cet argument et le marqueur explicite
`MacCareDevelopmentBuild=true` ; une distribution et un paquet sans marqueur
ignorent cet aperçu. `AppUpdater` présente alors la version fictive 0.2.99 et ses
notes identifiées comme simulation, sans démarrer Sparkle. Le bouton de téléchargement
ouvre seulement une alerte explicative. Aucun réglage n’est enregistré ; le prochain
lancement sans argument retrouve le fonctionnement normal. La copie quotidienne
n’est ni remplacée ni modifiée.

Validation : quatre tests de configuration passent, dont les gardes d’activation
de l’aperçu ; build Release et signature du paquet
`build/about-simulation/MacCare.app` vérifiés. Paquet Dev relancé sur À propos
avec l’argument de simulation ; version fictive, notes et contour orange confirmés
par lecture de l’interface et capture `build/about-qa/live-simulation.png`.
La synchronisation de la documentation interne reste suivie séparément.

## Historique du bouton jaune livré

**Publié dans [MacCare 0.2.20 (build 22)](https://github.com/M0okz/maccare/releases/tag/v0.2.20) le 9 novembre 2026.**
Ce statut remplace les mentions de développement non livré des étapes ci-dessous.
Les validations datées et leurs limites sont conservées.


9 novembre 2026 — **préparé en développement, non publié et non installé**.
Branche `codex/update-availability`, base produit `253abdc` (après PR #27).
La copie quotidienne reste MacCare 0.2.19 (21).

## Comportement

Un bouton jaune « Mise à jour disponible », avec symbole de téléchargement,
apparaît en haut à droite dans la barre native de la fenêtre principale.
Gregory a retenu son affichage commun à toutes les rubriques. La barre réserve
un espace flexible avant le bouton ; le texte reste visible même lorsque la
barre privilégie les icônes. Les fonds et accents des catégories sont conservés.
Le rappel n’apparaît pas dans l’accueil des autorisations initiales.

Le clic appelle le contrôleur Sparkle existant et ramène au premier plan son
panneau de mise à jour, avec le changelog de la version détectée. L’installation
reste une action distincte dans ce panneau. Aucun nouveau service de téléchargement,
aucun parseur de notes de version et aucun flux parallèle ne sont ajoutés.

`AppUpdater` adopte les rappels discrets de `SPUStandardUserDriverDelegate`.
Les recherches automatiques ordinaires publient la version disponible sans ouvrir
de fenêtre. Les versions critiques gardent la présentation native de Sparkle.
Les recherches manuelles gardent également le panneau natif. À la fin de la
session (report, version ignorée ou erreur), le bouton disparaît : les choix de
Sparkle continuent de faire foi.

Un contrôle en arrière-plan est lancé juste après le démarrage de Sparkle lorsque
la recherche automatique est activée. Le planificateur Sparkle reprend ensuite
la main ; aucun timer supplémentaire. Le réglage utilisateur, les signatures du
flux et des paquets, les contrôles avant extraction et les validations de la
chaîne de distribution restent identiques.

## Intégration

- `AppUpdater.swift` : propriétaire du contrôleur et du rappel, délégué isolé au
  MainActor, typecheck Swift 6 strict.
- `AppUpdateAvailabilityButton.swift` : texte, symbole, aide, version accessible,
  survol, état désactivé et retour d’appui commun qui respecte Réduire les animations.
- `AppUpdateAvailabilityToolbar.swift` : même position dans la barre native,
  fond partagé masqué sur macOS 26 et ultérieur, repli sur macOS 13 à 15.
- `MacCareApp.swift` et `RootView` : une instance commune de l’updater pour la
  fenêtre, le menu de recherche et les Réglages. La configuration AppKit existante
  s’applique aussi à la barre créée par SwiftUI.
- `DesignSystem.swift` : jaune de disponibilité `#FFD84D`, texte prune `#20152E`.

## Vérifications et limites

Le build Release arm64 et les trois tests de configuration des mises à jour
passent. Les types du rappel et le délégué passent également une compilation
Swift 6 avec contrôle de concurrence strict, ciblant macOS 13.

Un aperçu natif distinct (`org.maccare.qa.update-availability`) utilise les vrais
sources du bouton, de la barre et de l’updater, avec le vrai flux public signé.
Il ne crée ni modèle de batterie ni client d’assistant et ne partage pas le
domaine de préférences du produit. La version disponible 0.2.19 a été détectée
en arrière-plan ; aucune fenêtre ne s’est ouverte avant le clic. Le bouton,
sa version et son aide sont accessibles. Le clic a ouvert le panneau Sparkle
avec le changelog complet (Batterie, assistant, accessoires), puis « Pas maintenant »
a retiré le rappel. Aucune installation n’a été lancée depuis cet aperçu.

La composition de la fenêtre produit est compilée ; la campagne native de
navigation sur toutes les rubriques n’est pas déclarée effectuée. Ni campagne
VoiceOver complète, ni exécution réelle sur macOS 13 à 15, ni simulation d’une
mise à jour critique ne sont revendiquées. L’aperçu n’est pas un paquet de distribution.
Les preuves locales sont dans `build/update-availability-qa/` du worktree.
