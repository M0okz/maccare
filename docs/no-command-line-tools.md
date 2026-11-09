# Analyse Applications sans outils de développement

9 novembre 2026 — **correctif en développement, non livré**.
Branche `codex/no-command-line-tools`, base `c682107` après la livraison 0.2.20.
Le numéro et la signature de la copie installée ne sont pas modifiés.

## Incident et cause

La vérification de compatibilité appelait `/usr/bin/lipo -archs` pour chaque
exécutable. Sur un Mac sans Xcode ou Command Line Tools, le lanceur Apple peut
proposer d’installer les outils de développement. L’analyse courante de MacCare
ne doit pas dépendre de cet environnement de compilation.

## Correction

`ApplicationInsightsReader` lit les architectures via `ExecutableArchitectures`,
en processus avec `CFBundleCopyExecutableArchitecturesForURL`. Aucun binaire
analysé n’est chargé ou exécuté, aucun outil externe n’est lancé.

CoreFoundation ne reconnaît pas toutes les tables universelles FAT64. Un repli
lit uniquement les petits en-têtes : 64 entrées au maximum, table bornée à
2 Kio, taille et position de chaque tranche vérifiées avant lecture, CPU du
Mach-O cohérent avec sa table. Les tailles sont comparées par soustraction pour
éviter les dépassements ; les deux ordres d’octets sont couverts. Les formats
inconnus restent « compatibilité inconnue », sans appel à un outil de secours.

Les familles CPU sont normalisées (`arm64e` vers `arm64`, `x86_64h` vers
`x86_64`). La politique de version minimale tient compte des variantes déclarées
pour ne pas présenter une app utilisable comme définitivement incompatible.
Intel sur Apple Silicon reste un cas potentiellement utilisable via Rosetta.

## Régression et prévention

`app/Tests/NoDeveloperToolsTests/run.sh` compile le vrai inventaire et le vrai
scanner avec un lanceur témoin qui échoue si le scanner demande une commande.
Le test était rouge avant correction sur `/usr/bin/lipo` ; il passe après.
L’option `--installed-apps` vérifie aussi l’inventaire local sans publier les noms.
Le scan local de 48 apps a reconnu toutes les architectures sans commande.
Les contrôles de suppression d’installateurs sont exclus de cette sonde et
restent couverts par leurs tests propres.

Le script recherche aussi les références directes aux lanceurs d’outils de
compilation dans les sources exécutées par le produit. Il est exécuté dans la
CI et avant le build de distribution. Les scripts de construction/notarisation
restent autorisés à utiliser la chaîne de développement sur les runners.

Un chemin `lipo` existe encore dans le travail parallèle d’installation des mises
à jour, non fusionné dans cette base. Le nouveau contrôle le détecte : ce
consommateur devra réutiliser la lecture native avant sa livraison. Ses sources
et son index Git n’ont pas été modifiés par cette intervention.

## Validation et limites

Build Release arm64, suite Swift complète et 19 tests Python de release réussis.
Les tests natifs couvrent les familles Intel, ARM et PowerPC, les sous-types,
les tables universelles 32/64 bits, les tailles invalides, les en-têtes tronqués,
les débordements, les CPU incohérents et les données non exécutables.
Le binaire construit ne contient plus le chemin `/usr/bin/lipo`.

La machine de développement possède Xcode : les outils n’ont pas été retirés
pour reproduire physiquement l’absence de CLT. La sonde remplace uniquement le
lanceur de commandes afin de contrôler le déclencheur exact, tout en exécutant
le vrai code d’inventaire et d’analyse. Aucun test sur un autre Mac sans CLT ni
installation du correctif dans Applications n’est revendiqué ici.
Preuves locales : `build/no-command-line-tools-qa/`.
