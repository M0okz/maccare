# MacCare 0.2.21 — remplacée par 0.2.22

9 novembre 2026 — PR #29 fusionnée sur `0bfbe6b4bc7e98ca77864741d76c95f68178dec4`, après quatre contrôles verts. La CI de fusion et le workflow officiel `42713722898` réussissent. Le tag `v0.2.21` reste inchangé, build 23.

La vérification du DMG public a trouvé une erreur dans le parcours App Store : la chaîne de signature était transmise à `codesign --test-requirement` sans préfixe `=`. Le système la prenait pour le chemin d’un fichier et refusait l’opération avant l’installation. L’identité et la signature Developer ID du composant embarqué sont correctes. Le passage de la même expression avec `=` réussit sur ce même binaire.

La 0.2.21 est écartée de la distribution stable au profit de la 0.2.20 pendant la préparation de la 0.2.22. Le correctif et un test de compilation par `csreq` sont ajoutés à cette prochaine version ; une réussite CI seule ne suffit pas à certifier cet argument d’exécution. Le site n’a pas été déployé en 0.2.21. Les copies installées sont préservées.

Preuves : `build/release-0.2.21-qa/`, en particulier `public-verification.log` ; le DMG est démonté après le contrôle. Aucun appel App Store privilégié ni installation personnelle n’a été exécuté.
