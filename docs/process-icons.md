# Icônes des processus auxiliaires — Dev du 8 novembre 2026

Disponible dans [MacCare 0.2.15 (build 17)](https://github.com/M0okz/maccare/releases/tag/v0.2.15). Les mentions Dev/non livré ci-dessous conservent l’historique des vérifications antérieures à cette publication et leurs limites. Voir [la livraison et ses contrôles](releasing.md).

Correctif local sur `codex/helper-process-icons`, non publié après MacCare
0.2.14 (16). Le paquet `build/helper-icons/MacCare.app` est installé dans
`/Applications/MacCare Dev.app`, Dev 0.2.14 (build local 8), sans flux Sparkle.

## Résolution

`TrayProcessController.presentation(for:)` obtenait uniquement l’icône de
`NSRunningApplication` pour le PID. Un helper pouvait ne pas en fournir, alors
que son application possédait une icône ; le résultat vide était conservé avec
la présentation du processus.

`TrayProcessIconResolver` retrouve maintenant le premier paquet `.app` du chemin
absolu de l’exécutable. Un helper imbriqué dans `Helium.app/.../Helper.app/...`
reprend ainsi Helium et non le paquet technique intérieur. Si le chemin manque,
le paquet enregistré auprès de macOS peut fournir ce contexte. Les espaces,
accents, chemins transloqués et suffixes `.APP` sont pris en compte ; un suffixe
ressemblant à `.app` ne suffit pas. Le chargement depuis le disque exige un
paquet lisible déclarant un exécutable.

Une application ordinaire conserve son icône native lorsqu’elle correspond au
paquet identifié. Le repli lit l’icône du paquet via `NSWorkspace`. Un service
système sans application englobante, comme VTDecoderXPCService, garde le symbole
générique existant ; aucun rattachement n’est deviné depuis un nom de processus.
Les applications système réelles, par exemple Finder, gardent leur propre icône.

Noms, PID, classement CPU/mémoire et actions de fermeture ne changent pas. Le
cache reste limité à la vie du processus, identifié par PID et démarrage ; il
est purgé quand ce processus disparaît. Aucun nouveau suivi, droit ou scan de
répertoires d’applications n’est ajouté à l’exécution. Les images restent
masquées à l’accessibilité ; noms et actions restent lisibles séparément.

## Vérifications

18 tests ciblés réussis, dont 5 nouveaux tests pour la résolution des icônes :
helpers imbriqués, translocation/Unicode, icône native préservée, repli depuis
le paquet, services génériques et chemin manquant. Les suites existantes vérifient
aussi le cache par identité, la réutilisation de PID et les actions sur des
processus de test jetables. Build Release arm64 et signatures profondes strictes.

Contrôle dans le paquet natif, fenêtre RAM : Claude Helper (Renderer) affiche
l’icône de Claude, les rendus Codex gardent l’icône Codex et les noms/PID restent
séparés. Le processus bun.exe sans paquet d’application garde le symbole générique.
Helium ne figurait pas dans les six plus gourmands à cet instant : un probe local
compilant le même résolveur avec le vrai paquet Helium a confirmé que Helium Helper
(Aperitif Renderer) reçoit exactement l’image de Helium.app. Le repli générique
pour VTDecoderXPCService est vérifié par tests et par ce probe, sans prétendre
qu’il était visible dans la liste native. Le probe temporaire est supprimé après
contrôle ; ses résultats restent dans `build/helper-icons-qa/helium-validation.json`.

Pas de campagne complète VoiceOver/clavier, de test sur l’autre Mac physique,
ni de scénario natif de désinstallation d’une app pendant la lecture. La copie
quotidienne est conservée et la sauvegarde temporaire Dev est supprimée après
validation. Lancement avec `-battery.protection.resume NO`. Preuves :
`build/helper-icons-qa/` (tests, build, packaging et validation). Aucune publication.
