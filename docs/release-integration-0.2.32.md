# MacCare 0.2.32 — Veille Améthyste

MacCare 0.2.32 (build 34) a été publiée le 23 novembre 2026 pour les Mac Apple Silicon sous macOS 13 ou ultérieur. Le tag `v0.2.32` vise le commit `0aec7e2f108ea960d54b0abca79a5aa3f2d31572`. [Version publique](https://github.com/M0okz/maccare/releases/tag/v0.2.32) · [PR #41](https://github.com/M0okz/maccare/pull/41) · [CI de fusion](https://github.com/M0okz/maccare/actions/runs/45163683569) · [Signature et publication](https://github.com/M0okz/maccare/actions/runs/45164743807)

Le Dock, le premier lancement et la fenêtre À propos reprennent le petit écran violet de Veille Améthyste. Dans la barre des menus, le symbole monochrome ouvre le volet de suivi. Le bouton Analyser et les accents du volet utilisent la nouvelle palette.

## Contrôles de distribution

- La CI de branche, de PR et de fusion a réussi. La chaîne de publication a compilé et testé le paquet de distribution.
- Le DMG téléchargé depuis la release publique contient 16510266 octets. Son SHA-256 `bc4603c3c4699c6d4781a9c1cafc630757002c4ad832bfb617546acc7491ddab` correspond à la somme publiée et au manifeste.
- La signature Developer ID et les tickets de notarisation d’Apple ont été vérifiés sur l’image et sur l’application qu’elle contient. Gatekeeper a accepté MacCare. Les cinq exécutables contrôlés sont arm64.
- Les signatures Ed25519 du DMG et du flux Sparkle ont été vérifiées avec la clé qui valide aussi le flux de la 0.2.31. Le flux public annonce la 0.2.32 (build 34).
- Les icônes embarquées ont été comparées aux sources Veille Améthyste. Les vérifications du paquet public ont été réalisées en lecture seule. Le contrôle visuel a été effectué sur la DEV.

## Site public

Les 10 pages HTML et les trois nouvelles icônes correspondent aux fichiers du site après relecture en HTTPS. Le plan du site et les destinations de 276 liens, ancres et références de ressources internes ont été contrôlés. [Site MacCare](https://maccare.homeblack.fr/) · [Guide de prise en main](https://maccare.homeblack.fr/documentation/demarrer.html)
