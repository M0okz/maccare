# Livraison MacCare 0.2.22

10 novembre 2026 — [release publiée](https://github.com/M0okz/maccare/releases/tag/v0.2.22), build **24**. Tag `v0.2.22` sur `b73a43d45154c9adcf4087039cd90a2430e067c9`, après fusion de la [PR #30](https://github.com/M0okz/maccare/pull/30). [Workflow officiel](https://github.com/M0okz/maccare/actions/runs/42716751129) réussi.

## Changement livré

Cette version comprend l’installation de la PR #29 et la correction complémentaire de la PR #30. La 0.2.21 est écartée du flux stable après découverte, sur son DMG public, du préfixe manquant dans la commande de contrôle de signature App Store. L’expression en ligne est maintenant compilée par un test système et vérifiée sur le mas signé de la 0.2.22. [Constat de la 0.2.21](release-integration-0.2.21.md).

Dans **Applications → Mises à jour**, le bouton **Mettre à jour** lance le parcours d’installation adapté à l’app sélectionnée, avec progression et résultat. Sparkle cible le paquet externe ; Homebrew est réservé à la copie réellement gérée ; l’App Store utilise le mas embarqué avec une autorisation macOS ; les DMG/ZIP compatibles sont téléchargés et remplacent l’ancienne app après contrôles. Les PKG passent par l’installateur macOS puis une vérification de version.

L’analyse seule n’installe rien. Les apps ouvertes quittent après confirmation, sans arrêt forcé. Une seule installation est engagée à la fois ; l’annulation reste disponible avant installation. Les données hors du paquet sont conservées. Le correctif comprend la relecture directe du plist pour éviter une version périmée en cache. [Fonctionnement détaillé](application-update-installation.md).

## Contrôles

Les quatre contrôles de la PR #29 sont verts au commit `4bb6cc8`, puis ceux du correctif de la PR #30 au commit `05752e9`. La CI de fusion réussit sur le commit du tag. Les tests sont rejoués par la chaîne officielle avant accès aux clés. Tests locaux : 360 XCTest exécutés (trois tests réseau facultatifs ignorés, aucun échec), 259 Swift Testing et 19 tests Python réussis. Les deux parcours réseau d’archives signées ont été exécutés séparément : MacCare 0.2.19 → 0.2.20, puis **PhotoCraft 0.21.0 → 0.22.0 avec ses vrais DMG officiels**, sur des copies isolées. Mauvais SHA refusé sans modification de l’ancienne copie, préférences de test préservées ; extraction ZIP avec lien symbolique sortant refusée.

Le DMG public téléchargé est vérifié : signature Developer ID, tickets de notarisation et agrafage app/DMG, Gatekeeper « Notarized Developer ID », cinq exécutables arm64, version et canal du helper cohérents. Le mas embarqué satisfait exactement l’exigence Developer ID `org.maccare.mas`, équipe MacCare, requise avant l’exécution privilégiée. Les signatures Ed25519 du flux et du DMG sont valides avec la clé publique de la copie quotidienne ; latest est identique au flux signé.

DMG : **16414623 octets** ; SHA-256 `714ae86aa4e389a8f0b5e2aafb62faadb7541ed5267dba7bdaa2fe3348fbb58c`.

Dix pages publiques sont actualisées et vérifiées identiques aux sources en HTTPS, avec le nouveau parcours d’installation, les liens, la taille et l’empreinte. Le conteneur est sain ; les remplacements atomiques préservent droits et propriétaires. Les pages antérieures correspondent à Git, qui fournit le retour arrière. Six pages Outline sont actualisées puis relues, en conservant contenu et emplacement antérieurs. Suivi de livraison : [#104](https://todo.homeblack.fr/tasks/7155).

## Limites et copies installées

Aucune mise à jour des apps personnelles Homebrew/App Store, autorisation administrateur réelle, session Sparkle tierce complète ou installation PKG réelle n’est revendiquée. Pas de campagne VoiceOver complète ni de nouvelle validation matérielle batterie. Les captures web restent les anciennes captures explicitement signalées. Certaines installations et signatures demandent encore le mécanisme de l’éditeur ; une détection ne garantit pas l’installation.

La distribution n’a pas été lancée ni installée pendant la publication. Les empreintes des copies installées sont préservées. Le bouton a été inspecté dans le gestionnaire natif en Dev ; les remplacements réels ont visé exclusivement des fixtures possédées.

Preuves : `build/release-0.2.22-qa/` et `build/application-update-install-qa/`. Les téléchargements, montages et scripts temporaires de publication sont nettoyés après validation ; les JSON, journaux et captures sont conservés.
