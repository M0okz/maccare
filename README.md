# MacCare

MacCare est une application native de maintenance pour macOS, écrite en SwiftUI
avec un moteur de scan et de nettoyage en Rust. La première distribution cible
les Mac Apple Silicon, à partir de macOS 13.

Site et téléchargement : <https://maccare.homeblack.fr/>, sources dans [site/](site/README.md).

## Fonctions

- Analyse des caches, journaux et fichiers temporaires, avec revue avant suppression.
- Recherche de gros fichiers, de doublons et exploration de l’occupation du disque.
- Gestion des applications, résidus, autorisations et éléments de démarrage.
- Entretien : index Mail, caches et instantanés locaux facultatifs, Spotlight,
  autorisations du dossier personnel et cache DNS.
- Suivi de la batterie, de la mémoire, du processeur et du réseau Wi-Fi.
- Contrôle facultatif de la charge sur les Mac et versions de macOS compatibles.
- Mises à jour de MacCare avec Sparkle, distribuées par les releases GitHub.

La rubrique Batterie avancée dépend des capacités du Mac et de son firmware.
Ses fonctions, essais et limites de disponibilité sont décrits dans
[la documentation Batterie avancée](docs/battery-advanced.md).

MacCare est en développement. Les DMG de validation de la CI ne sont pas des
releases notariées. Les versions de distribution passent par une chaîne séparée
de signature Developer ID, notarisation Apple et signature Sparkle.

## Installation et mises à jour

Les versions distribuables sont publiées dans les
[releases GitHub](https://github.com/M0okz/maccare/releases).
Glissez MacCare depuis le DMG vers Applications, puis lancez l’app depuis ce dossier.
L’assistant système reste facultatif et nécessite votre approbation dans macOS.

Dans une version distribuée, **MacCare → Rechercher les mises à jour…** lance une
recherche manuelle. **Réglages → Général** permet de désactiver les recherches
automatiques. L’installation d’une mise à jour nécessite votre action. Aucun jeton
GitHub n’est intégré dans l’app et aucun profilage Sparkle n’est activé.

## Architecture

- `app/Sources/MacCare/` : interface SwiftUI et modèles de l’application.
- `core/` : moteur Rust, règles de nettoyage et contrôles de sûreté.
- `app/Sources/CMacCareCore/` : frontière C vers le moteur.
- `app/Sources/MacCareHelper/` : assistant XPC géré par SMAppService.
- `app/Sources/MacCareBattery/` : mesures et politique de protection de la batterie.
- `app/installer/` : création et contrôle du DMG.
- `app/release/` : versionnement, signature du flux Sparkle et distribution.
- `.github/workflows/` : tests, DMG de validation et releases macOS.

## Construire depuis les sources

Prérequis : un Mac Apple Silicon, les outils Swift/Xcode actuels, Python 3.11+ et
un accès aux distributions officielles Rust et Sparkle.

```sh
./app/build.sh
./app/package.sh
./app/create-dmg.sh --skip-build
```

Le script de build installe une chaîne Rust isolée avec empreintes épinglées sous
`build/toolchains/` et contrôle que les objets liés conservent le minimum macOS 13.
Sparkle 2.10.1 est épinglé dans SwiftPM. Le paquet manuel embarque et signe son
framework. Les sorties se trouvent sous `build/` ; aucune installation n’est faite
dans `/Applications` par ces scripts.

```sh
cargo test --locked --manifest-path core/Cargo.toml
swift test --package-path app --scratch-path build/swift-tests --build-system native --arch "$(uname -m)" -Xlinker -L"$PWD/core/target/release"
python3 -m unittest discover -s app/release/tests -v
python3 app/release/test_signatures.py
```

Les builds de développement n’activent pas Sparkle sans flux et clé publique de
distribution. Les détails de la CI et des secrets sont dans
[la procédure de release](docs/releasing.md).

## Sûreté et limites

Le moteur revalide l’identité des fichiers et le confinement des chemins avant
suppression ; les liens symboliques et arbres protégés sont refusés. La mise à la
corbeille est privilégiée quand l’action le permet. Les actions irréversibles et
les opérations système demandent une confirmation explicite.

La réduction des instantanés Time Machine locaux est facultative : elle retire des
points de restauration locaux, sans viser les sauvegardes externes ou réseau.
L’espace réellement récupéré dépend de macOS. Spotlight est réindexé en arrière-plan.

Les mesures mémoire sont des estimations d’utilisation, pas la pression mémoire
de macOS. Les débits Wi-Fi comprennent le trafic local. Le test Internet est lancé
uniquement à la demande. Les fonctions de charge dépendent du matériel et de macOS ;
la limite native nécessite macOS 26.4+ et la disponibilité des interfaces système.

## Licence

Le code MacCare est distribué sous [licence MIT](LICENSE).
Les composants tiers conservent leurs propres licences, indiquées dans
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
