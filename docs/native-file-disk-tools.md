# Images PNG et santé des disques

## État de développement

Évolution locale du 7 novembre 2026, branche `codex/native-file-disk-tools`,
après `226be66` (mas embarqué). Non publiée. La copie quotidienne
`/Applications/MacCare.app` reste en 0.2.8 (10), sans remplacement ni signature.
Les paquets de QA sont exclusivement sous `build/`.

## Mes fichiers → Alléger des images PNG

L’entrée est disponible avant l’analyse et depuis le bilan de Mes fichiers.
L’outil ouvre un sélecteur natif de PNG, puis un sélecteur de dossier pour
**Créer les copies optimisées**. Résultat par image : taille avant/après,
copie créée, déjà optimisée ou problème de lecture. Le gain annoncé concerne
les copies ; ce n’est pas de l’espace libéré tant que les originaux sont conservés.
**Afficher les copies** ouvre leur sélection dans le Finder.

oxipng 10.2.1 est lié directement au moteur Rust, sans exécutable à installer,
via `maccare_optimize_png_copy`. Les features par défaut sont désactivées :
traitement séquentiel à priorité utilitaire, hors du thread principal. Les
options de compression préservent les pixels, la profondeur, les couleurs,
l’alpha et les chunks de métadonnées. Les optimisations de pixels transparents,
les réductions de couleur/profondeur et le changement d’entrelacement sont désactivés.

Une demande est limitée à 100 images, 64 Mio et 32 mégapixels par image, avec
une borne de décompression de 256 Mio et un budget d’optimisation de 15 secondes
par image. Les PNG invalides, fichiers non réguliers et liens symboliques sont
refusés. Le moteur ne suit pas de lien à l’ouverture. Aucun fichier original
n’est ouvert en écriture. Les copies utilisent un nom distinct et une création
exclusive : les collisions produisent un suffixe numérique et n’écrasent rien.
Une image qui ne gagne pas en taille ne produit pas de copie. L’arrêt du lot
prend effet après l’image en cours ; les copies terminées restent disponibles.

Les métadonnées internes PNG sont conservées ; les attributs Finder, permissions
et dates du fichier original ne sont pas recopiés. Les copies sont créées avec
les permissions utilisateur 0600. Pas de parcours automatique de photothèque,
ni de service en arrière-plan pour les images.

## Outils → Santé des disques

Le diagnostic se trouve dans **Outils**, au choix explicite de Gregory.
**Espace disque ne reçoit aucun nouveau composant de santé.** L’ouverture du
diagnostic lit les informations du disque de démarrage ; un sélecteur natif
permet de choisir un autre volume local monté. Les montages, démontages et
renommages actualisent les choix. Une déconnexion ramène au disque de démarrage.

La carte montre le statut rapporté, la température et l’endurance consommée
lorsqu’ils sont disponibles. Les détails repliables donnent modèle, heures,
mises sous tension, données écrites, erreurs d’intégrité et réserve disponible.
Les valeurs absentes restent absentes, sans faux zéro ni état sain inventé.
L’endurance consommée est l’estimation du fabricant, pas une durée de vie restante.

smartctl 7.5 r5714 est embarqué dans `Contents/Helpers/smartctl`, sans Homebrew,
sans service smartd ni installation de pilote. Seules les options fixes de lecture
`-j -H -A -i -q noserial -B <base embarquée> <disque physique>` sont utilisées.
Aucun auto-test ni changement de réglage SMART n’est déclenché. Les numéros de
série sont exclus de la sortie. Les processus sont bornés à 12 secondes.

Le volume du chemin est résolu par Foundation, puis ses propriétés par `diskutil`.
Un volume APFS doit avoir un seul support physique identifiable ; le lecteur suit
ce support et son disque entier. Les disques virtuels et cas ambigus ne retombent
jamais arbitrairement sur disk0. Les bits de statut smartctl sont distingués :
échec d’invocation/lecture versus alerte matérielle valide à afficher.
Les unités NVMe écrites sont converties en octets à raison de 512 000 octets/unité.

## Barre des menus → Stockage interne

Le clic sur le bloc **Stockage interne** ouvre un sous-volet natif à côté du volet.
Il présente la santé du disque interne (statut, température et endurance), puis
l’espace disponible et utilisé. La lecture n’a lieu qu’à l’ouverture de ce détail.
**Voir la santé des disques** ouvre directement le diagnostic Outils ; l’action
existante d’exploration du stockage reste disponible séparément. Aucun diagnostic
matériel n’est ajouté dans la section Espace disque.

## Packaging et redistribution

`embed_smartmontools.py` télécharge le DMG officiel et les sources correspondantes,
avec SHA-256 figés dans `app/vendor/smartmontools/manifest.json`. Il monte le DMG
en lecture seule, extrait le PKG sans l’installer, conserve uniquement smartctl
et sa base de disques, puis démonte et supprime son matériel temporaire. Le Mach-O
universel est réduit à l’architecture du paquet, contrôlé (minimum macOS 13 ou
antérieur et bibliothèques système uniquement), puis signé avec le runtime durci
avant la signature de MacCare. La release contrôle aussi cette architecture.

COPYING GPLv2-ou-ultérieure, AUTHORS et l’archive exacte des sources non modifiées
sont livrés dans `Contents/Resources/smartmontools`, avec la base et le manifeste.
Les licences et versions de la dépendance oxipng et de son arbre verrouillé sont
livrées dans `Contents/Resources/oxipng`. `release.json` enregistre les versions.
Aucun fichier n’est installé dans les répertoires système ou Homebrew.

## Vérifications et limites

Paquet final vérifié : `build/native-tools-final/MacCare.app`, MacCare Dev 0.2.11,
Apple Development, runtime durci pour smartctl. Build Release arm64, signature
profonde stricte de l’app et des composants, minimum macOS du moteur et des outils
validés. Versions embarquées : oxipng 10.2.1, smartctl 7.5 r5714, mas 7.0.0.

Tests réussis : **98 tests Rust** (deux ignorés préexistants), **17 XCTest** et
**14 Swift Testing** (avec cas paramétrés), **19 tests Python** de release.
Les PNG sont couverts par une fixture possédée RGBA avec pixels transparents et
texte : pixels décodés identiques via ImageIO, original inchangé, texte conservé,
refus des liens/fichiers invalides/images trop grandes/APNG, noms en collision
préservés et absence de copie plus lourde. Les tests du lecteur couvrent les
unités NVMe, la distinction alertes/échecs, les volumes virtuels/ambigus et la
résolution APFS vers le bon disque physique.

Contrôle natif effectué avec `PATH=/usr/bin:/bin` et
`-battery.protection.resume NO`. Parcours Mes fichiers → Alléger → sélecteurs
natifs → copie et résultat : **16 555 octets → 214 octets** sur la fixture
très compressible, sans modification de l’original. Ce ratio n’est pas une
promesse pour les fichiers courants. Le diagnostic Outils charge réellement le
SSD APPLE SSD AP0512Q : aucune alerte, endurance consommée 4 %, erreurs
média 0, réserve 100 %, température variable. Les détails sont accessibles par
le contrôle de divulgation natif.

Depuis Fenêtre → Afficher le volet MacCare → Stockage interne, le vrai popover
contient état matériel, température, endurance et capacités. Son arbre natif
et le clic Voir la santé des disques vers le gestionnaire Outils sont vérifiés.
La capture du volet principal n’inclut pas toute la surface du popover ; pas de
preuve photographique isolée de celui-ci. Le diagnostic Outils reste ouvert
à la fin. La section Espace disque n’a aucun diff fonctionnel dans cette évolution.

La copie quotidienne conserve le SHA-256 d’exécutable
`78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`.
Aucune release, notarisation de distribution, installation quotidienne ou
campagne complète VoiceOver/clavier/variantes d’affichage pendant cette tâche.
Les téléchargements, montages, extraction, ancien paquet de QA et PNG de travail
ont été nettoyés ; seules les preuves et le paquet final restent sous build.
Preuves : `build/native-tools-qa/validation.json`, journaux Rust/Swift/Python,
`png-runtime.json`, `smart-runtime.json`, build et packaging.

Le lecteur fonctionne sans élévation sur le SSD du M1 de QA. Cela ne prouve pas
la compatibilité de tous les disques, boîtiers USB, modèles Intel ou anciens macOS.
Les supports qui ne transmettent pas leurs informations affichent une indisponibilité
explicite. Aucun pilote supplémentaire n’est installé pour les prendre en charge.
Pas de promesse de détection de toute panne, ni de notation de durée de vie restante.
Les PNG animés/APNG sont refusés explicitement pour borner le travail et la mémoire
à une image fixe. Les profils colorimétriques variés et tous les types de PNG fixes
nécessitent une campagne plus large que la fixture possédée de cette intervention.
