# Intégration MacCare 0.2.17

Préparation du 9 novembre 2026, **publiée dans MacCare 0.2.17 (build 19)**, ancienne branche
`codex/release-0.2.17`. Gregory demande de réunir tous les commits produit,
fusionner main et fermer les branches pour une nouvelle release.

## Branches réunies

- `codex/apple-device-batteries` et `codex/standardized-subviews`, tête `40a61d1` :
  lecteur mobile, catalogue hybride d’applications, guides publics, sous-vues.
- `codex/apple-device-wifi`, tête `c3d9317` : configuration Wi-Fi explicite,
  dédoublonnage USB/réseau, validation réelle après deux relances sans câble.
- `codex/device-battery-alerts`, tête `d64c5aa` : option désactivée par défaut,
  seuil réglable, alertes iPhone/iPad frais, Watch exclue des alertes automatiques.
- `codex/bundled-mas` et `codex/native-file-disk-tools` : code déjà livré dans
  0.2.12. `git range-diff c424edc^..c424edc cf62181^..cf62181` confirme le même
  patch de code, avec un contexte documentaire différent et la mention du
  cherry-pick. La fusion historique `88cd083` conserve l’arbre produit actuel
  tout en rattachant ces commits pour permettre une fermeture sans perte.
- `claude/site-0.2.9` est déjà ancêtre de main ; aucun ancien contenu du site
  n’est réintroduit.

Les deux conflits de `docs/development-builds.md` conservent les deux historiques.
Aucun conflit fonctionnel. Les worktrees de QA sont conservés, détachés après
fusion avant suppression des branches ; leurs paquets et preuves restent présents.

## Validation de l’ensemble

Release arm64 et signature stricte du paquet Dev 0.2.17 (22) réussies.
329 XCTest, dont un test réseau live facultatif ignoré, sans échec ;
247 Swift Testing et 19 tests Python de packaging passent. Fixtures natives
DeviceBatteryProbe, SMCWire et PowerUIBridge réussies sous leurs contrôles.

Le lecteur signé du paquet intégré retourne sans câble iPhone 86 % et Watch
74 %, réponse complète en 2,989 s. L’interface Appareils Apple relit Wi-Fi actif,
modification désactivée sans USB. Réglages → Menu affiche l’alerte appareil
désactivée et son seuil à 20 %. Aucun réglage personnel n’est changé par la QA.
Les validations visuelles détaillées des autres composants restent celles de
leurs branches ; une campagne complète VoiceOver/clavier n’est pas revendiquée.

Preuves : `build/release-0.2.17-qa/`. Les copies installées de MacCare et MacCare
Dev ne sont ni remplacées ni re-signées. Le défaut du matin ne s’est pas reproduit
pendant les deux relances Wi-Fi, mais longue veille et redémarrages restent
non testés. L’énergie des démons et des appareils sur la durée n’est pas mesurée.

## Documentation et accès de livraison

Notes utilisateur : [0.2.17](release-notes/0.2.17.md). Au moment de la publication,
le bastion Homelab était injoignable et la synchronisation Outline/Vikunja ainsi
que le redéploiement du site restaient bloqués avant authentification API.
La reprise demandée ensuite par Gregory a rétabli les accès via les comptes de
service existants. Le site est déployé et Outline synchronisé puis relu ; voir
[la clôture vérifiée](release-0.2.17-completion.md). Aucun secret n’est journalisé.

## Publication et contrôle du paquet public

La [PR #24](https://github.com/M0okz/maccare/pull/24) est fusionnée sur main au
commit `22d72fab270e55320a008188c02963fffa83a000`. Les CI de branche
[42629066003](https://github.com/M0okz/maccare/actions/runs/42629066003), de PR
[42629106200](https://github.com/M0okz/maccare/actions/runs/42629106200) et de main
[42630611537](https://github.com/M0okz/maccare/actions/runs/42630611537) réussissent.
Le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42630770167)
réussit et publie la release stable le 9 novembre à 14:09:53 UTC.

Le DMG public téléchargé et son app sont signés Developer ID, notariés et
agrafés ; Gatekeeper accepte l’app. Les cinq exécutables sont arm64, le helper
porte la version 0.2.17, le build 19 et le canal distribution. Les manifestes
et composants tiers sont présents. Les signatures Ed25519 du flux et du DMG
sont vérifiées avec la clé publique de la copie quotidienne ; le flux latest
est identique au flux signé de la release. L’app distribuée n’est pas lancée.

DMG : **16 049 174 octets**, SHA-256
`f787279babc1d33b67fc236fa2b726d1be153294cb014d2bd2c9438d6b7b332f`.
Les deux copies installées gardent leurs empreintes de référence. Huit branches
locales et trois distantes intégrées sont supprimées, leurs worktrees conservés
détachés. Le nouveau chantier `codex/battery-cards`, apparu pendant la livraison,
reste en cours et préservé ; il ne fait pas partie du tag figé de la 0.2.17.

Après relance de la Dev intégrée, les ronds natifs affichent iPhone 84 % et
Watch 74 %, reçus à 14:57. Lors du premier affichage intégré, seuls les
accessoires macOS étaient visibles ; la sonde séparée lisait les appareils,
puis la relance les a affichés. Aucune cause n’est établie pour cette absence
initiale ; ne pas transformer cette campagne en garantie de disponibilité continue.

Le site et les neuf pages de documentation servent maintenant la 0.2.17, ses
liens, sa taille et son empreinte. Les dix réponses HTTPS sont identiques aux
sources `5e33750`, le conteneur est sain et les droits sont conservés. Les copies
temporaires ciblées sont supprimées. Les 10 pages et 207 liens internes des
sources avaient passé les contrôles statiques. Outline est mis à jour puis relu,
avec contenu antérieur et emplacement préservés ; voir
[la clôture et ses preuves](release-0.2.17-completion.md).
