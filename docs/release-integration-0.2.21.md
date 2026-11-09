# Préparation de MacCare 0.2.21

9 novembre 2026 — publication demandée par Gregory pour livrer le correctif
de la PR #29 et permettre l’installation depuis le gestionnaire Applications.

La version passe à 0.2.21 sur `codex/application-update-installation` avant
la dernière passe CI. Le tag ne sera créé qu’après réussite des contrôles et
fusion de la PR. La chaîne officielle reconstruit, teste, signe et notarie
l’app et le DMG, puis génère les signatures Sparkle et publie les assets vérifiés.

[Notes utilisateur](release-notes/0.2.21.md).
[Détails de l’installation et limites de QA](application-update-installation.md).
Les tests locaux précédents comptent 359 XCTest (trois cas réseau facultatifs
ignorés), 259 Swift Testing et 19 tests Python des outils de release sans échec.
Les deux tests d’archives signées ont été exécutés séparément, dont PhotoCraft
0.21.0 → 0.22.0. Une installation sur les apps personnelles n’est pas revendiquée.

Le site et Outline seront actualisés et relus après vérification des assets
publics. Aucun remplacement ni lancement des copies quotidiennes n’est demandé.
