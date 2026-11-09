# Retrait des applications et données associées

## État — 9 novembre 2026

**Livré dans [MacCare 0.2.16 (build 18)](https://github.com/M0okz/maccare/releases/tag/v0.2.16).** Branche de préparation `codex/stable-metrics-history`, désormais fusionnée et fermée. MacCare Dev
0.2.15 (19) est installée dans `/Applications/MacCare Dev.app`, signée Apple
Development sans flux Sparkle. La publication est 0.2.16 (18) ; la copie
quotidienne `/Applications/MacCare.app` 0.2.8 (10) est préservée.

## Comportement

Dans Applications → Gérer mes applications, le paquet et toutes les données
associées détectées sont désormais cochés. Chaque élément peut être décoché.
Les données seules peuvent être retirées en conservant le paquet. Le bouton et
le texte de conséquence décrivent la sélection et le mode corbeille/permanent.
Les résidus d’applications absentes restent une sélection distincte.

Le retrait ne ferme pas automatiquement une application en cours. Cette
correction n’ajoute ni fermeture forcée ni gestion des processus ouverts.

Les listes du gestionnaire et des mises à jour rendent toute la ligne cliquable,
espaces vides compris. Les lignes de fichiers du désinstalleur utilisent un
Toggle natif avec une étiquette couvrant le nom, le chemin et la taille : une
case ou sa ligne bascule une seule fois. La sélection reste exposée à
l’accessibilité. Les menus contextuels permettant de montrer le fichier dans
le Finder sont conservés.

## Cause du refus et correction

Le modèle soumettait tous les éléments au périmètre du dossier personnel.
Un paquet sous `/Applications` échouait donc avec `outside-scope`. Un simple
élargissement de la racine n’aurait pas suffi, car le nettoyage générique protège
aussi `/Applications` récursivement.

`Remover.uninstall` sépare le chemin exact du paquet choisi et les autres
éléments. Le paquet est traité dans `/Applications` ou `~/Applications`, avec
une règle à liste d’inclusion limitée à son nom complet et une sélection ne
contenant que ce chemin exact. Les données sont traitées dans le dossier
personnel. Le moteur existant applique cette liste d’inclusion aux deux modes,
sans retirer la protection globale de `/Applications` dans le nettoyage.
Identité de fichier et chemins sont encore vérifiés ; un paquet remplacé depuis
le scan et un paquet voisin injecté dans la sélection restent refusés.

Le modèle appelle la même opération pour la corbeille et la suppression directe,
agrège leurs résultats, puis retire de son catalogue les paquets disparus.
Aucun nouvel accès privilégié ou changement de réglage macOS n’est ajouté.

## Vérifications

Le test intégrant `UninstallModel.cleanSelected` échouait avant correction avec
`0` retrait et `outside-scope` pour un paquet factice dans `/Applications`.
Le test de présélection échouait aussi. La suite complète réussit ensuite :
**294 XCTest + 247 Swift Testing = 541 tests**. Les cas ciblés incluent noms avec
guillemets, barre oblique inverse et emoji, mode permanent, données seules,
paquet voisin et identité remplacée.

Dans la Dev installée, le clic à droite de la ligne B (390,295), sans effet avant
correction, sélectionne bien B. Les deux cases sont cochées. Un clic dans la
zone vide de la ligne de préférence (1190,415) décoche, puis un second recochage
fonctionne. Les deux applications factices A et B et leurs préférences donnent
chacune **2 mis à la corbeille**, sans refus, et disparaissent du catalogue.
Dans les mises à jour, le clic dans l’espace vide de la seconde ligne ouvre bien
son détail. Aucun logiciel personnel n’a été désinstallé pour ces contrôles.

Les quatre éléments de test ont été nettoyés. Le retrait direct depuis la
corbeille était refusé par macOS au processus de commande : le Finder a remis
uniquement ces quatre éléments à leur emplacement d’origine, puis ils ont été
supprimés par leur chemin exact après vérification de leur identifiant. Aucun
réglage de sécurité ni purge globale de la corbeille n’a été utilisé.

Preuves locales : `build/applications-fix-qa/red-uninstall.log`,
`red-selection.log`, `tests-full.log`, `build.log`, `package.log`,
`validation.json` et `fixture-cleanup.json`. Le parcours VoiceOver complet,
l’autre MacBook physique et la fermeture d’un logiciel réellement ouvert ne
sont pas validés par cette campagne.
