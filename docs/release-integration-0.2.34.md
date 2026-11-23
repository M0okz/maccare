# MacCare 0.2.34 — Tableau des processus

La version 0.2.34 (build 36) est disponible pour les Mac Apple Silicon sous macOS 13 ou ultérieur. Le tag `v0.2.34` vise `60d922019a35460c7d80c217a8ba5d158f3a19fe` et inclut les modifications validées en Dev sur `a6362f0`. [Notes de version](https://github.com/M0okz/maccare/releases/tag/v0.2.34) · [PR #43](https://github.com/M0okz/maccare/pull/43) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45273009755) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45273023007)

L’accueil regroupe les processus par application, signale les charges supérieures à 40 % de CPU et ouvre une fiche détaillée au clic. La sélection de la souris disparaît à la fermeture. Un clic sur le fond ou Échap ferme la fiche. La fenêtre principale s’ouvre à 1 311 × 773 points et adapte son minimum à la taille de l’écran.

## Distribution

- Les contrôles de branche, de PR et de fusion ont réussi. Le workflow de release a construit et testé le paquet sur le commit du tag.
- Le DMG public téléchargé pèse 16609466 octets. Son SHA-256 `8a19aab44106ccf7e1ae03d4d15c8f0495622bd5221a78deebe23c115b82c67f` correspond au manifeste et à la somme publiée.
- Le DMG et l’application montée en lecture seule ont passé les contrôles de signature, de notarisation et de Gatekeeper. Les cinq exécutables distribués sont signés Developer ID et ciblent arm64.
- Le flux public Sparkle propose la version 0.2.34 (build 36). Les signatures Ed25519 du flux et du DMG ont été vérifiées avec la clé qui valide aussi le flux de la version 0.2.33.

## Site

Les dix pages et le plan du site ont été relus en HTTPS et correspondent aux sources. Le contrôle a vérifié 276 références internes. [Téléchargement](https://maccare.homeblack.fr/#telecharger) · [Guide de prise en main](https://maccare.homeblack.fr/documentation/demarrer.html)
