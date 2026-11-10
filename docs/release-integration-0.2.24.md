# MacCare 0.2.24 — correctif iStat Menus, 10 novembre 2026

**Livré dans [MacCare 0.2.24 (build 26)](https://github.com/M0okz/maccare/releases/tag/v0.2.24)**,
tag `v0.2.24` sur `4b7372b08ed5ac8bb70eab8c9e23ae076b78a47e`, après fusion de
la [PR #33](https://github.com/M0okz/maccare/pull/33).

Le runner tronquait la liste ZIP officielle d’iStat Menus au milieu d’un chemin,
créant un faux chemin absolu. Il lit maintenant les métadonnées complètes avec
une limite explicite de 16 Mio et refuse un dépassement. Les protections contre
les chemins dangereux, les contrôles de signature, d’éditeur, d’empreinte,
Gatekeeper et d’architecture restent appliqués. L’exception exacte pour le build
2394 d’iStat Menus reconnaît 7.50.2, dont le paquet déclare encore 7.50.

## Vérifications du code

La [CI de branche](https://github.com/M0okz/maccare/actions/runs/42807536251),
la [CI de PR](https://github.com/M0okz/maccare/actions/runs/42807545672),
la [CI après fusion](https://github.com/M0okz/maccare/actions/runs/42808960383)
et le [workflow officiel de release](https://github.com/M0okz/maccare/actions/runs/42808969287)
réussissent.

Build Release arm64 ; 365 XCTest exécutés (5 parcours optionnels ignorés),
269 Swift Testing et 19 tests Python réussis localement. Le vrai remplacement
iStat 7.50 (2355) vers 7.50.2 (2394) est exécuté séparément sur une copie possédée :
SHA-256 des archives officielles, signature Y93TK974AT, Gatekeeper, préférences
de test conservées, puis absence de nouvelle proposition de la même mise à jour.
Les grandes listes valides, une traversée au début d’une grande liste, le
dépassement de limite et l’extraction face à un lien symbolique sortant sont
couverts. La garde contre les appels aux outils de développement passe.

## Paquet public et flux utilisateur

DMG public : **16425654 octets**, SHA-256
`153499599cce2362c7dc0bbc5c1b29e2eaf3f54d6a313c239e54c0701dc1a616`.
Empreintes du téléchargement, du fichier SHA-256, du manifeste release.json et
de l’asset GitHub identiques. Signature Developer ID, intégrité et ticket Apple
du DMG vérifiés. L’app montée en lecture seule passe codesign strict profond,
notarisation et Gatekeeper ; les cinq exécutables sont arm64. L’exigence de
signature du mas embarqué, les métadonnées de l’assistant et l’absence du chemin
runtime lipo sont vérifiées. Signatures Ed25519 du DMG et du flux validées avec
la clé publique de la copie quotidienne ; le flux latest correspond à la release.

Le site et les dix pages HTTPS correspondent aux sources : version, lien,
taille, empreinte et guide actualisés. Conteneur maccare-site sain, structure HTML
et liens locaux vérifiés. Trois pages Outline (architecture, développement,
journal) mises à jour et relues avec contenu antérieur et placement conservés.
Suivi Vikunja #107 dans HomeLab, vue Kanban.

## Limites

La copie quotidienne, la Dev installée et les apps personnelles sont conservées,
empreintes avant/après identiques. Le paquet distribué n’a pas été lancé ou installé.
Ni iStat ni ses helpers ne sont lancés dans le test ; la gestion des agents après
lancement par l’éditeur reste hors de cette validation. La confirmation sur le
second Mac, les anciens macOS et une campagne VoiceOver complète restent à faire.

Pour Bitwarden installé depuis l’App Store, l’utilisateur signale seulement la
fenêtre macOS d’autorisation administrateur, sans erreur ensuite. Elle demande
le mot de passe de la session Mac, pas celui du coffre. Le parcours App Store
reste inchangé et aucune installation App Store personnelle réussie n’est
revendiquée. Voir [la documentation App Store](app-store-updates.md).

Preuves locales : `build/istat-archive-qa/` et `build/release-0.2.24-qa/`.
Les téléchargements, montages et scripts temporaires sont nettoyés après les
contrôles ; les journaux et preuves JSON sont conservés.
