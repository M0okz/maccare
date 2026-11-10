# Détection des mises à jour App Store

Disponible dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), publiée le 7 novembre 2026. Les états Dev et les validations datées ci-dessous décrivent les paquets précédents et conservent leurs limites de QA.

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

## Vérification dans la branche d’accueil — 7 novembre 2026

Le commit mas embarqué est réuni aux évolutions d’accueil et aux outils PNG/disques
dans `codex/dashboard-summary-cards`. Le paquet `build/branch-integrated/MacCare.app`
actualise la Dev installée, sans remplacer la copie quotidienne. mas 7.0.0,
signature du composant, architecture arm64, licences et fonctionnement réel avec
`PATH=/usr/bin:/bin` sont vérifiés. Le gestionnaire natif affiche **App Store :
Aucune mise à jour détectée** ; les deux résultats Homebrew restent distincts.
Les limites sur l’absence d’entrée App Store réelle restent applicables.
Voir [la revue globale et les tests complets](branch-integrated-review.md).

## Publication 0.2.12 — 7 novembre 2026

Ces évolutions sont publiées dans [MacCare 0.2.12 (build 14)](https://github.com/M0okz/maccare/releases/tag/v0.2.12), tag `v0.2.12` sur `46a510ff8086af7f6f6a1427e9cf8f42d09b4355`, après fusion de la [PR #19](https://github.com/M0okz/maccare/pull/19). La branche `codex/dashboard-summary-cards` est supprimée localement et sur le remote. Ce statut remplace celui de développement non livré des évolutions d’accueil, mas embarqué, PNG et santé des disques décrites précédemment.

Le [workflow de release](https://github.com/M0okz/maccare/actions/runs/42355768168) est réussi. Les CI de branche, de PR et de fusion passent ; la revue locale compte 269 XCTest, 242 Swift Testing, 98 tests Rust et 19 tests Python réussis, avec contrôles PowerUI sans setter natif et contrôles Sparkle positifs/négatifs réussis. Le DMG public téléchargé, les quatre exécutables arm64, les signatures Developer ID, les tickets Apple et Gatekeeper sont vérifiés. Signatures Ed25519 du flux et du DMG validées avec la clé publique ; le flux latest correspond à la release. Licences, manifestes et archive source smartmontools présents dans le paquet.

DMG : 15917141 octets, SHA-256 `9beb668bfac13099b3ed14c08791285c616636c7a9deb5c3317470bbf97a4029`. Le site public pointe vers ce paquet, avec taille et empreinte correspondantes ; le HTML HTTPS correspond aux sources et le conteneur reste sain. Aucune installation quotidienne effectuée : `/Applications/MacCare.app` demeure en 0.2.8 (10), empreinte inchangée. La Dev installée demeure identifiée 0.2.12 (2). Les limites de QA datées restent applicables ; l’application de distribution n’a pas été lancée pendant cette livraison. Preuves : `build/release-0.2.12-qa/`.


## Autorisation administrateur signalée — 10 novembre 2026

Sur le second Mac, Bitwarden installé depuis l’App Store affiche uniquement
le dialogue macOS d’autorisation du script lancé par MacCare ; aucune erreur
ensuite n’est signalée. Ce parcours utilise `mas` embarqué, copié dans un dossier
privé appartenant à root puis contrôlé avec l’exigence de signature MacCare avant
exécution sur le seul identifiant App Store sélectionné. La fenêtre demande le
mot de passe administrateur de la session Mac, jamais celui du coffre Bitwarden.
Le libellé « script » vient de l’élévation AppleScript utilisée actuellement.
Ce retour ne prouve pas l’achèvement d’une mise à jour App Store ; aucun changement
de ce mécanisme n’est inclus dans le correctif ZIP 0.2.24.

## Correctif de session utilisateur — préparation 0.2.25, 10 novembre 2026

Un nouveau retour du second Mac montre `Failed to get sudo uid` après acceptation
de l’autorisation. Cette erreur précise remplace l’incertitude du retour précédent
qui ne montrait que la fenêtre macOS. Le problème est l’environnement de lancement,
sans preuve d’un mot de passe incorrect.

mas 7.0.0 lit `SUDO_UID` et `SUDO_GID` dans ses getters ProcessInfo lorsqu’il est
lancé comme root. L’élévation AppleScript ne remplit pas ces variables. MacCare
capture maintenant `getuid()` et `getgid()` dans la session GUI avant élévation,
puis les exporte explicitement dans le script. Il ne prend pas les identifiants
d’un environnement hérité ni ceux du compte administrateur qui autorise l’action.
Une identité root ou invalide est refusée avant construction du script.

Le staging privé, la copie avant contrôle de signature, l’exigence Developer ID
`org.maccare.mas`, les arguments fixes et le seul identifiant App Store choisi
restent appliqués. Le mot de passe n’est ni lu ni conservé par MacCare.

Reproduction : une sonde signée Developer ID utilise les getters officiels
non modifiés de mas 7.0.0, sans changer les credentials ni installer d’app. Le
script complet de production échoue avec le même `Failed to get sudo uid` avant
correction ; il passe après, même avec un environnement SUDO vide ou usurpé à 0.
Les cas root/identifiants invalides et le refus d’un outil non signé sont couverts.
Une installation App Store privilégiée réelle n’a pas été exécutée sur une app
personnelle ; la confirmation du correctif Bitwarden sur le second Mac reste à faire.

Branche `codex/app-store-session-context`, non livrée à ce stade.
Source : [mas 7.0.0 — getters de session](https://github.com/mas-cli/mas/blob/v7.0.0/Sources/mas/Utilities/Processes/ProcessInfo.swift).
