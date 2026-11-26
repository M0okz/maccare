# Retrait des applications et données associées

## Désinstallation avec autorisation administrateur — 26 novembre 2026

Publié dans [MacCare 0.2.47](https://github.com/M0okz/maccare/releases/tag/v0.2.47) (build 49). Le changement `7097097` a été testé dans la copie DEV `build/uninstall-app-components/MacCare.app`. [Contrôles de distribution](release-integration-0.2.47.md).

Dans **Applications → Gérer mes applications**, le gestionnaire identifie le paquet choisi, les assistants et extensions de son espace de noms, leurs conteneurs, scripts, caches et temporaires Darwin, ainsi que leurs listes de documents récents. Il reconnaît aussi deux identifiants usuels d’anciens assistants de connexion. Les conteneurs propres à l’app sont cochés et leur ligne signale qu’ils peuvent contenir des documents. Le bouton **Tout cocher** de la section Données associées permet d’inclure les profils et composants facultatifs en un clic.

Les préférences, caches et dossiers de support portant l’identifiant de l’app dans `/Library` peuvent être choisis. Un agent ou daemon de lancement tiers et son outil ou dossier de support sont proposés lorsque le nom du plist, son Label et le chemin de son exécutable concordent avec l’application. Ces composants communs au Mac demandent une sélection explicite. Un groupe déclaré est sélectionnable si l’inventaire ne trouve aucun autre propriétaire. Une seconde copie ou une autre application qui revendique le groupe protège les données communes. Le système et les fichiers sans rattachement établi restent en dehors du retrait.

Le clic traite les fichiers avec les droits de la session. Une sélection qui rencontre un refus d’écriture, ou contient un paquet appartenant à un autre compte, peut déclencher **une autorisation administrateur macOS**. Le lot contient uniquement les chemins validés par le moteur. Si le paquet nécessite cette autorisation, il est traité en premier dans le lot. L’assistant ponctuel `MacCareHelper --uninstall-selection` vérifie l’empreinte de la sélection après le dialogue et contrôle l’identité de chaque élément avant de le déplacer. Il ouvre les répertoires sans suivre les liens. En mode Corbeille, sa destination est celle de l’utilisateur connecté. En mode définitif, le retrait passe par un répertoire privé temporaire. Le service XPC utilise toujours son protocole de maintenance existant.

Le bouton **Détails** donne le chemin, la taille et le résultat de chaque élément. Un échec sur le paquet conserve les données qui en dépendent. Une annulation de l’autorisation est indiquée explicitement. Les emplacements protégés par une politique macOS peuvent encore renvoyer une erreur après autorisation.

**Vérifications.** 21 tests ciblés réussis, dont le contrôle du paquet signé, des deux modes de retrait, de l’annulation, d’une sélection modifiée et des clics aux trois densités d’écran. Dans MacCare Dev, un paquet factice et sept fichiers associés ont été détectés. Un refus d’écriture provoqué a ouvert la fenêtre système attribuée à MacCare Dev. L’annulation a laissé les huit éléments en place. Lors d’un second essai, six éléments sont passés à la Corbeille avant la demande pour les deux conteneurs gérés par macOS. L’acceptation de cette dernière demande avec un compte administrateur reste à vérifier. Une troisième sélection a retiré définitivement une application factice et ses deux caches, avec trois chemins confirmés à l’écran et sur disque. Les fichiers de test ont été nettoyés. Preuve locale dans `build/uninstall-app-components/validation.json`. Le cas réel de Barbee et le second MacBook n’ont pas été rejoués.

## Présélection du désinstalleur — 24 novembre 2026, en développement

Dans Applications → Gérer mes applications, la revue indique le chemin de la copie choisie et la raison du choix sur chaque ligne. Le paquet et les préférences, caches, journaux, états de fenêtres ou agents rattachés à son identifiant sont présélectionnés. Les profils connus de navigateurs, conteneurs personnels, données web, dossiers de support et correspondances par nom demandent une sélection individuelle. Les données seules peuvent toujours être retirées.

Quand une deuxième copie du même identifiant est détectée, ses données associées sont protégées dans les deux modes de retrait. Une application homonyme protège aussi les chemins attribués par nom. Les éditions reconnues de Firefox qui utilisent le même dossier de profils le protègent mutuellement. Les conteneurs de groupe identifiés par le catalogue ou par les groupes déclarés dans la signature restent visibles et protégés. Le chemin de l’autre application est indiqué lorsqu’il est connu.

La revue interroge les dossiers Applications habituels ainsi que les copies enregistrées auprès de macOS ou en cours d’exécution pour les identifiants recherchés. Une copie hors ligne, ou hors catalogue et inconnue de macOS, échappe à cette détection. Le retrait contrôle de nouveau les propriétaires avant d’agir sur les données. Un échec de retrait du paquet conserve les données de la sélection.

**Référence locale** — branche `codex/app-action-pills`, état de travail sur `b4c7083`. Les décisions sont dans `UninstallReview.swift`, leur application dans `UninstallModel.swift`, `UninstallerView.swift` et `Remover.swift`. Cette évolution est en DEV. La section du 9 novembre ci-dessous décrit la version livrée à cette date.

**Vérifications** — 11 tests ciblés du désinstalleur. La suite Swift complète compte 399 XCTest dont 7 ignorés et 295 tests Swift Testing, sans échec. Deux apps de test signées avec le même identifiant ont été installées dans Applications. Dans MacCare Dev, le paquet A était coché et la préférence partagée désactivée avec le chemin de B. Après le passage de A à la Corbeille, puis après un second essai en retrait définitif sur le paquet DEV final, B a été relancée et a lu la même valeur qu’avant le retrait. Un test couvre également une copie apparue entre analyse et exécution, dans les deux modes. La case et sa raison ont été relues dans l’arbre d’accessibilité macOS. VoiceOver et le second MacBook physique restent à vérifier. La preuve locale est dans `build/uninstall-shared/validation.json`.

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
