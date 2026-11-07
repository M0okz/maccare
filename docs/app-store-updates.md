# Détection des mises à jour App Store

## Fonctionnement

MacCare embarque **mas 7.0.0** dans `Contents/Helpers/mas`. La détection App Store
ne dépend ni de Homebrew, ni du PATH, ni d'une installation système de mas.
`AppStoreUpdates` exécute uniquement `outdated --inaccurate --json` hors du thread
principal. Il conserve seulement le nom et les versions installée/disponible.
Les autres métadonnées renvoyées par mas ne sont ni conservées ni affichées.

Les sources App Store, Homebrew (casks) et Sparkle (NetNewsWire) restent distinctes.
L'absence du composant embarqué signale une vérification incomplète avec une
invitation à réinstaller MacCare. Les erreurs d'exécution ou de décodage ne
deviennent jamais des résultats « à jour ». L'action **Ouvrir l’App Store** ouvre
l'application système. MacCare n'installe aucune mise à jour et ne propose plus
de commande mas à copier, puisque l'outil reste interne au paquet.

## Assemblage reproductible

`app/release/embed_mas.py`, appelé par `app/package.sh`, télécharge l'installateur
officiel correspondant à l'architecture. Version, URL et SHA-256 sont figés dans
`app/vendor/mas/manifest.json` ; les empreintes proviennent des assets officiels
de v7.0.0. L'installateur est seulement extrait avec `pkgutil --expand-full`,
jamais exécuté. Aucun fichier n'est installé dans `/usr/local` ou `/opt/homebrew`.

L'assemblage vérifie l'empreinte avant extraction, l'architecture du Mach-O, son
minimum macOS 13, ses liens vers les seules bibliothèques système et la licence
du payload. Une différence interrompt l'assemblage. Les fichiers téléchargés et
extraits sont supprimés automatiquement.

mas est signé avant l'app avec la même identité et le runtime durci. La
distribution ajoute l'horodatage et notarise le paquet complet par le parcours
existant. Son contrôle d'architecture inclut mas et `release.json` enregistre sa
version. Aucun binaire issu de Homebrew n'est repris pendant l'assemblage.

Les licences de mas et de ses onze dépendances Swift figées sont conservées
dans `app/vendor/mas/`, y compris les NOTICE Apache et la licence Hitch publiée
dans son README. `Package.resolved` donne les révisions source. Ces fichiers sont
copiés dans `Contents/Resources/mas` et référencés par `THIRD_PARTY_NOTICES.md`.

## Limites

Le mode standard de mas compare Spotlight au catalogue Apple. Leur actualisation
peut différer temporairement de celle de l'App Store. `--accurate`, qui commence
puis annule des téléchargements, reste exclu. Les apps iOS/iPadOS ne sont pas
couvertes par mas. Ses frameworks privés Apple peuvent nécessiter une mise à
jour lors d'une future version de macOS. Les assets fournis sont arm64 et x86_64 ;
la distribution actuelle de MacCare reste Apple Silicon.

## Validation du 7 novembre 2026

Évolution locale sur `codex/bundled-mas`, issue de `main` à `5730039`. Non publiée,
non installée dans `/Applications/MacCare.app` (copie quotidienne 0.2.8).
Le paquet de QA est `build/bundled-mas/MacCare.app`, identifié MacCare Dev.
Contrôles réussis : build Release arm64, signature profonde stricte de l'app et
signature du composant mas (runtime durci, même équipe), **19 tests Python** de
release, **9 XCTest** de présentation/NetNewsWire et **5 Swift Testing** App Store
(dont un test décliné en trois cas invalides). Les fixtures de deux mises à jour
vérifient le compteur, la source et les versions avant/après. Le composant absent,
les erreurs de service et les réponses JSON invalides sont couverts sans repli
vers Homebrew.

Exécution réelle du mas embarqué avec `PATH=/usr/bin:/bin` : version 7.0.0,
12 entrées installées, aucune mise à jour détectée, codes de sortie nuls.
Lancement du paquet Dev avec ce PATH et `-battery.protection.resume NO`, puis
Applications → Analyser → Voir les mises à jour → État des sources :
**App Store : Aucune mise à jour détectée**. Les deux résultats Homebrew restent
identifiés comme tels. Fenêtre laissée ouverte sur ce gestionnaire.

La copie quotidienne reste en 0.2.8, SHA-256 de l'exécutable
`78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.
Les paquets Dev préexistants n'ont pas été remplacés. Preuves locales :
`build/bundled-mas-qa/{build.log,package.log,tests.log,runtime.json}`.

Aucune mise à jour App Store n'étant disponible, l'affichage d'une entrée réelle
et le clic sur **Ouvrir l’App Store** ne sont pas validés en runtime ; la remontée
non vide est validée par les fixtures. Pas de notarisation de distribution ni
de campagne complète VoiceOver/clavier pendant cette QA de développement.
Les versions macOS anciennes et le matériel Intel nécessitent une validation
runtime distincte ; les contrôles de Mach-O ne la remplacent pas.
