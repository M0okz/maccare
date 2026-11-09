# Synchronisation Outline clôturée — batterie faible des appareils

**Synchronisé et relu le 9 novembre 2026**, lors de la clôture de MacCare 0.2.17.
Le texte ci-dessous conserve l’état historique du blocage et les éléments à
reporter ; il ne décrit plus une action en attente. Les fonctions sont publiées,
les limites datées restent valides. Voir [la clôture et ses preuves](release-0.2.17-completion.md).

## Historique de la demande de synchronisation


9 novembre 2026, branche `codex/device-battery-alerts`, base `5f76971`.
Référence : [contrat et vérifications](device-low-battery-alerts.md).

La demande corrigée concerne uniquement la **batterie faible**, avec réglage
activable/désactivable. Aucun développement d’alerte d’extinction ou
d’indisponibilité ne fait partie de cette branche.

L’accès prescrit a été retenté avec `homelab.py bw-exec --project` sur le
worktree de batterie faible, pour l’entrée `Outline - API documentaire`.
Résultat : code 2, avant accès documentaire confirmé :

```text
Homelab environment failed (file, format, command or timeout); no values displayed
```

Le diagnostic Homelab de la tentative précédente avait échoué de la même manière.
Ce résultat ne démontre ni un refus d’authentification Outline ni une panne de
son API. Aucun secret n’est copié ici ; la synchronisation n’est pas confirmée.

À reprendre : lire puis mettre à jour l’index et les chapitres 02, 03, 04, 06,
08 et 11, préserver le contenu sans rapport et l’emplacement, puis relire les
pages. Consigner le développement non livré, le seuil initial de 20 % réglable,
l’option désactivée par défaut, les niveaux directs de trois minutes au plus,
la Watch non datée exclue, la déduplication persistante et le réarmement à
seuil + 5 points, le cache partagé sans scan Bluetooth permanent, les 41 tests,
l’aperçu clair/sombre isolé et les copies installées inchangées. La note de
synchronisation Wi-Fi antérieure reste distincte et n’est pas effacée.
