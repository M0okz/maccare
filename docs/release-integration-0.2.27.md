# MacCare 0.2.27 — À propos, 14 novembre 2026

**Livré dans [MacCare 0.2.27 (build 29)](https://github.com/M0okz/maccare/releases/tag/v0.2.27)**,
[tag `v0.2.27`](https://github.com/M0okz/maccare/tree/v0.2.27) sur
`40c98e8507d2a11f6dfb3e780b0c39d6da643430`, après fusion de la
[PR #36](https://github.com/M0okz/maccare/pull/36).

## Comportement livré

L’entrée **À propos** apparaît sous **Mes outils**. Un contour orange et un
symbole de téléchargement signalent une mise à jour disponible, y compris dans
la navigation réduite ; la sélection et la valeur accessible sont conservées.
Le bouton jaune de la barre de titre est supprimé.

La page regroupe l’icône et la version installées, les nouveautés reçues par
Sparkle, l’action de téléchargement et les liens vers le site, la documentation
et le code source. Le menu macOS À propos ouvre cette page. Le panneau Sparkle
conserve le téléchargement et l’installation à la demande, les contrôles de
signature, les recherches automatiques et les choix de report.

Les notes sont du texte natif sélectionnable et défilant, sans accès réseau
supplémentaire ni exécution de HTML. Un lien vers les versions reste disponible
lorsque les notes intégrées ne peuvent pas être présentées.

L’aperçu `--preview-available-update` exige le marqueur explicite de paquet Dev.
La distribution l’ignore. L’aperçu 0.2.99 montré à Gregory est fictif ; son bouton
n’effectue ni téléchargement ni installation et aucun état n’est persisté.

## Vérifications

- 378 XCTest, dont 7 parcours facultatifs ignorés, 269 Swift Testing et 19 tests
  Python de packaging réussissent localement.
- Quatre lancements de la sonde avec 640 transitions de disponibilité, sans
  exception ; compilation isolée des vraies vues et du configurateur de fenêtre.
- Captures à 1200 × 800, 1200 × 720 et 860 × 620 avec/sans disponibilité relues,
  puis contrôle de la vraie fenêtre Dev avec contour et notes fictives.
- CI de [branche](https://github.com/M0okz/maccare/actions/runs/43588619515),
  [PR](https://github.com/M0okz/maccare/actions/runs/43588645157), puis
  [chaîne officielle](https://github.com/M0okz/maccare/actions/runs/43589378271)
  réussies. Le contenu du merge correspond exactement à l’arbre testé de la PR.

La première tentative a été bloquée par Apple (HTTP 403 : accord obligatoire
manquant ou expiré). Gregory a régularisé l’accord ; le contrôle d’accès à la
notarisation a ensuite réussi avant la relance de la chaîne officielle.

## Paquet public et documentation

DMG : **16478527 octets**, SHA-256
`d26b8ba27ed2dade0c9c2ba436d5830ce93a5724882700cdc4dc3134dcfaefc3`.

Après téléchargement depuis la release publique : empreinte, fichier SHA-256,
manifest et métadonnées GitHub cohérents ; signatures Developer ID, tickets
Apple app/DMG, intégrité de l’image et Gatekeeper validés. App montée en lecture
seule, cinq exécutables arm64, version/canal du helper et marqueur distribution
conformes. Signatures Ed25519 du flux et du DMG vérifiées avec la clé publique de
la copie quotidienne ; le flux latest correspond à la release.

Les dix HTML du site public correspondent aux sources en HTTPS. Les 246 liens et
ancres internes, les identifiants et les titres sont vérifiés. Le conteneur est
sain, les propriétaires et droits sont préservés. La couverture horaire des HTML
n’a pas été confirmée ; les sources Git précédentes étaient identiques à la
production et les copies temporaires ciblées ont été supprimées après contrôle.
Six pages Outline sont actualisées et relues, avec contenu antérieur et placement
conservés. Suivi : **Homelab #128**.

La copie quotidienne reste en 0.2.26. La publication ne l’a ni remplacée ni
re-signée ; l’app distribuée n’a été ni lancée ni installée pour ces contrôles.
Les archives téléchargées et montages de vérification sont nettoyés. Preuves
locales : `build/release-0.2.27-qa/` et `build/about-qa/`.

Limites : aucune installation réelle d’une mise à jour pendant cette campagne,
ni nouvelle campagne complète VoiceOver/clavier, ni exécution sur macOS 13–15
revendiquée. Les limites matérielles et d’installation des versions précédentes
restent applicables.
