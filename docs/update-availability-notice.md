# Rappel de mise à jour de MacCare

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
