# MacCare 0.2.35 — Boutons en pilule et curseur

MacCare 0.2.35 (build 37) est disponible pour Apple Silicon sous macOS 13 ou ultérieur. Les boutons utilisent un libellé centré et le pointeur prend la forme d’une main sur les commandes actives. Dans la fiche processus, « Quitter » et « Forcer à quitter » ouvrent chacun une confirmation. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.35).

## Construction et vérifications

Le tag `v0.2.35` vise `249c512d0e7e62e28036f822575cdc30d3bf2a9c` et inclut le commit fonctionnel `b4c7083`. La sonde de barre d’outils compile les fichiers du bouton en pilule et du curseur utilisés dans la vue À propos. Les contrôles de la branche, de la PR, de la fusion et de la chaîne de distribution ont réussi. [PR 44](https://github.com/M0okz/maccare/pull/44) · [CI de la PR](https://github.com/M0okz/maccare/actions/runs/45287186718) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45289034556) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45289040275).

Sur le Mac de développement, les 685 tests Swift exécutés et les 21 tests Python du packaging ont réussi. Sept tests Swift optionnels ont été ignorés. Le survol et les confirmations ont été vérifiés dans MacCare Dev sous macOS 27.0.1. La vérification visuelle sous macOS 13 et 14 reste à effectuer.

## Distribution

- Le DMG public téléchargé pèse 16676735 octets. Son SHA-256 `195ba8328a96f6bfbebf6392d8241f2ce66f19497ed1f77436aed5ebdf631f91` correspond au manifeste et à la somme publiée.
- Les tickets de notarisation Apple et les contrôles Gatekeeper ont été vérifiés sur le DMG et l’application montée en lecture seule. Les cinq exécutables contrôlés portent une signature Developer ID Application et ciblent arm64.
- Le flux Sparkle stable propose 0.2.35 (build 37). Les signatures Ed25519 du flux et du DMG ont été vérifiées avec la clé publique qui valide également le flux 0.2.34.

## Site

Les 10 pages HTML et le plan du site relus en HTTPS correspondent aux sources. Le contrôle a vérifié 216 références internes. [Télécharger MacCare](https://maccare.homeblack.fr/#telecharger) · [Guide de prise en main](https://maccare.homeblack.fr/documentation/demarrer.html).
