# MacCare 0.2.25 — App Store et alertes de version, 10 novembre 2026

**Livré dans [MacCare 0.2.25 (build 27)](https://github.com/M0okz/maccare/releases/tag/v0.2.25)**,
tag `v0.2.25` sur `c6c8483a55d6ea296b792cf564b6f0eeb40ddb1e`, après fusion de
la [PR #34](https://github.com/M0okz/maccare/pull/34).

## Comportement livré

L’élévation App Store transmet désormais les identifiants réels de la session GUI
attendus par mas 7.0.0 : `SUDO_UID` et `SUDO_GID`. Cela corrige le refus
`Failed to get sudo uid` après l’autorisation administrateur. Les identités root
ou invalides sont refusées. Le staging privé, la copie avant contrôle de signature,
l’exigence Developer ID et le seul identifiant App Store sélectionné sont conservés.

Le bouton jaune est aligné à droite sur macOS 26+ avec un espace flexible SwiftUI.
La même barre reste gérée par SwiftUI, sans réintroduire le conflit NSToolbar/KVO.
Les bannières macOS de nouvelles versions de MacCare sont réglables dans Général,
soumises à l’autorisation système et au choix de recherche automatique. Une seule
alerte par build, aucune demande de permission en arrière-plan ; le clic ouvre
le panneau Sparkle même si la fenêtre principale était fermée. La fin de session Sparkle ou
l’attention utilisateur invalide aussi une livraison encore en cours. Les autres
notifications gardent leur route. Aucun serveur APNs ou nouveau timer n’est ajouté.
Les alertes restent liées aux recherches Sparkle existantes ; elles n’arrivent pas
instantanément à la publication et ne sont pas envoyées quand MacCare est quitté.

## Vérifications

Les [CI de branche](https://github.com/M0okz/maccare/actions/runs/42825219615),
[de PR](https://github.com/M0okz/maccare/actions/runs/42825230650),
[après fusion](https://github.com/M0okz/maccare/actions/runs/42826952820)
et le [workflow officiel](https://github.com/M0okz/maccare/actions/runs/42826962553)
réussissent.

373 XCTest exécutés localement (5 parcours optionnels ignorés, sonde mas active),
269 Swift Testing, build Release arm64 et 19 tests Python réussis. La sonde signée
utilise les getters officiels de mas sans changer de credentials : même erreur
avant, contexte correct après, y compris avec SUDO vide ou usurpé à 0. Root et
identifiants invalides, outil non signé et chemins hostiles sont couverts.

Le bouton passe quatre lancements et 640 transitions avec une identité de toolbar,
256 assertions de position et une marge droite de 8 points, contre 928 avant.
Le vrai flux public signé Sparkle 0.2.24 est utilisé par une app isolée 0.2.19 :
transport de notification injecté, une alerte acceptée, route depuis fenêtre fermée,
vrai changelog, report puis recherche manuelle et préférence désactivée observés
avec CUA. Déduplication persistante, refus, désactivation, échec puis reprise et
annulation pendant l’autorisation ou pendant la livraison sont testés.

## Paquet public et documentation

DMG : **16445407 octets**, SHA-256
`cd896a0534954f78a2beff5602ecf2b6455a3a5c17df5145fef59e13cbe08f5d`.
Empreintes du fichier, du manifeste, du fichier SHA-256 et de l’asset GitHub
identiques. DMG signé Developer ID, ticket Apple et intégrité vérifiés. App montée
en lecture seule : signature profonde stricte, notarisation, Gatekeeper et cinq
exécutables arm64 validés. Exigence de signature mas et métadonnées de l’assistant
validées. Signatures Ed25519 du flux et du DMG vérifiées avec la clé publique connue ;
latest correspond à la release. Le chemin runtime lipo reste absent.

Dix pages HTTPS correspondent aux sources mises à jour, avec lien, version,
taille, empreinte et guide ; HTML et liens locaux vérifiés, conteneur sain.
Trois pages Outline sont mises à jour et relues avec contenu antérieur et placement
conservés. Suivi HomeLab #108, vue Kanban.

## Limites et copies conservées

La tentative de bannière système réelle a été refusée par macOS pour la sonde.
Après une relance avec une nouvelle identité de test, CUA n’a pas résolu cette app.
L’apparition d’une bannière réellement autorisée et son clic système ne sont donc
pas revendiqués vérifiés sur ce poste ; le routage et le vrai panneau Sparkle le
sont avec transport injecté. Une installation App Store privilégiée réelle de
Bitwarden sur le second Mac reste à confirmer. Aucune app personnelle n’est mise
à jour, aucun paquet public n’est installé ou lancé pendant cette livraison.
Les empreintes des copies quotidienne et Dev installées sont conservées.
Les anciens macOS et une campagne VoiceOver complète restent à vérifier.

Preuves : `build/mas-user-context-qa/` et `build/release-0.2.25-qa/`. Les sondes,
téléchargements et fichiers temporaires sont nettoyés ; journaux et JSON conservés.
Voir [les notifications](app-update-notifications.md) et [le correctif App Store](app-store-updates.md).
