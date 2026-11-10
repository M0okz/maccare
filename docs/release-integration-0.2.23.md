# Livraison MacCare 0.2.23

10 novembre 2026 — [MacCare 0.2.23 (build 25)](https://github.com/M0okz/maccare/releases/tag/v0.2.23), tag sur `a3c3f98f646fa27202607b47c6879969ca6eb72b`, après les PR #31 et #32. [Workflow officiel](https://github.com/M0okz/maccare/actions/runs/42789605501) réussi.

## Correctifs livrés

Le rapport distant porte sur MacCare 0.2.20 (22), macOS 27.2, avec une exception `removeObserver → SwiftUI.AppKitWindowController.updateToolbarIfNeeded` au lancement. La sonde native a reproduit cette même pile sur macOS 27.0.1. SwiftUI et WindowConfigurator réaffectaient la même barre d’outils ; SwiftUI en reste désormais le seul propriétaire et l’élément du rappel garde une identité déclarative stable. Les styles de fenêtre et l’accessibilité du bouton sont conservés.

La PR #31 supprime l’appel à lipo dans l’inventaire et le staging des mises à jour. Une lecture CoreFoundation et des en-têtes Mach-O bornés la remplacent, sans exécuter l’app analysée. Aucun téléchargement de Command Line Tools n’est requis. Les signatures, l’éditeur, le SHA-256 lorsqu’il est fourni, la compatibilité et Gatekeeper restent contrôlés.

## Validation

La sonde avant correction plante avec la même exception que le rapport. Le correctif passe quatre lancements et 640 transitions ; le passage est répété avec le bouton et les styles de production. Le contrôle minimal avec l’ancien groupe SwiftUI et seulement l’affectation AppKit retirée passe aussi, ce qui confirme le conflit de propriété. La CI et la chaîne officielle compilent cette sonde ; son exécution graphique est explicite sur une session WindowServer active. Le vrai AppUpdater, le rappel et la recherche manuelle sont également exercés dans une app isolée contre le flux signé 0.2.22 : ouverture du changelog puis report, deux fois, sans plantage ni installation. La preuve est native-preview-qa.json.

361 XCTest sans échec (quatre cas réseau facultatifs ignorés), 269 Swift Testing et 19 tests Python réussissent en local. Le test opt-in **ArtCraft Launcher 0.16.1 → 0.17.0** est exécuté séparément avec les vrais DMG officiels, sur une copie possédée : contrôles, remplacement et préférences de test préservés. Les 48 applications locales sont inventoriées sans commande externe ; l’audit des sources runtime ne trouve pas de lanceur de développement. Les CI de branche/PR/fusion et la chaîne de publication réussissent.

Le DMG public téléchargé est vérifié : Developer ID, notarisation et agrafage de l’app et du DMG, Gatekeeper, cinq exécutables arm64, métadonnées du helper, exigence de signature du mas et absence du chemin runtime `/usr/bin/lipo` dans l’exécutable MacCare. Les signatures Ed25519 du flux et du DMG sont vérifiées avec la clé publique de la copie installée ; latest correspond à cette release. DMG : 16416851 octets ; SHA-256 `99554baf3ea026c5ddd101d42cf1549bf2929235c530b3889515717038c40ab3`.

Dix pages HTML publiques sont déployées avec droits/propriétaires conservés, puis relues en HTTPS, identiques aux sources. Le conteneur est sain. Les pages antérieures correspondent à Git et les remplacements temporaires sont retirés. Six pages Outline sont mises à jour puis relues, avec contenu et emplacement antérieurs conservés. Suivi : [#106](https://todo.homeblack.fr/tasks/7157).

## Limites

Le Mac distant sous 27.2 n’a pas encore été revalidé avec ce paquet ; la reproduction et la validation graphique sont effectuées sur 27.0.1. Pas de nouvelle campagne sur les anciens macOS ni de VoiceOver complet. Les autres mécanismes de mise à jour gardent les limites de la 0.2.22. Aucune app personnelle n’est mise à jour ; aucune autorisation administrateur réelle n’est acceptée pendant la QA. Le paquet distribué n’est ni lancé ni installé pendant la vérification publique. Les copies installées restent inchangées.

Preuves : `build/update-runtime-regression-qa/` et `build/release-0.2.23-qa/`. Les archives, montages, sondes compilées et scripts temporaires sont nettoyés après contrôle ; les JSON et journaux sont conservés.
