# Alertes CPU et batterie

Disponible depuis [MacCare 0.2.8 (build 10)](https://github.com/M0okz/maccare/releases/tag/v0.2.8), publiée le 6 novembre 2026
(heure de Paris). Installation de cette version vérifiée dans
`/Applications/MacCare.app` via Sparkle, depuis 0.2.6 (8). Le paquet installé
correspond au binaire public signé et notarié. Les validations de développement
ci-dessous restent datées et conservent leurs limites.

Fonctionnalité préparée dans la [PR nº 4](https://github.com/M0okz/maccare/pull/4),
sur la branche préexistante `codex/menu-bar-alerts`. La base initiale est
`8868649`, puis la branche est mise à jour avec `main`. L’harmonisation de
Nettoyage, incluse dans cette même PR, est décrite dans `cleaning-managers.md`.
L’intégration du code ne remplace pas la version utilisateur installée.

Les trois alertes réutilisent `MenuBarAlertPresenter` et le contour déjà validé :
largeur 340 points, flou AppKit natif, pointe raccordée, trait sombre fin,
apparences claire/sombre, fermeture par Échap ou clic extérieur.

## CPU élevé

La charge globale doit atteindre 85 % pendant 120 secondes consécutives.
Le contrôleur lit lui-même les compteurs CPU toutes les 5 secondes (`CPULoadCounter`) :
le `TrayMetricsStore` ne tourne que lorsqu’un écran l’affiche. Chaque lecture donne
la charge moyenne depuis la précédente, donc une baisse de moins de 5 secondes peut
passer inaperçue. Une mesure absente/invalide, un retour sous le seuil, un intervalle
de plus de 15 secondes ou la veille réinitialisent la fenêtre. Une mesure âgée de plus
de 15 secondes ne permet pas de présenter l’alerte.

Deux lectures du `TrayProcessSampler`, espacées d’une seconde, attribuent
ensuite le CPU aux applications accessibles. Jusqu’à trois applications
graphiques de l’utilisateur à au moins 50 % d’un cœur sont proposées, triées
par CPU ; aucune consommation mémoire minimale n’est imposée. MacCare et les
processus protégés restent exclus. Les pourcentages par application concernent
le processus principal et un cœur, tandis que la charge du Mac concerne
tous les cœurs ; l’aide précise cette différence.

« Quitter » demande une fermeture normale en réutilisant les vérifications
d’identité du chemin mémoire. Aucune fermeture automatique ou forcée.
« Voir l’activité » ouvre la fenêtre CPU existante, via l’action `openWindow`
capturée dans `TraySceneLifecycle`.

## Protection batterie interrompue

L’alerte exige une protection attendue mais non confirmée pendant 30 secondes.
L’intention est initialisée depuis la préférence de reprise, activée après une
activation confirmée et retirée lors d’une désactivation volontaire.
Une erreur de connexion ne suffit pas à effacer cette intention de notification.
Cet état est informatif : les règles et commandes de protection ne changent pas.

Un assistant absent, une erreur, une restauration ou une session inactive
peuvent constituer une interruption. Une pause normale de charge, y compris
thermique ou en attente du secteur, n’est pas une interruption tant que la
session reste saine. Pour le backend natif par politique, le délai normal
d’enregistrement de la limite est respecté ; une limite encore non enregistrée
après ce délai n’est plus considérée confirmée.

Le bouton « Vérifier la protection » ouvre Batterie. Il ne réactive pas
l’assistant, n’enregistre aucun service et n’applique aucune limite.

## Fin d’opération batterie

Une recharge ponctuelle est terminée après observation de son état en cours,
puis de sa fin à 100 % sur secteur, avec une session saine appartenant au
demandeur. La limite habituelle doit être de nouveau enregistrée ; si cet
enregistrement est en cours, l’observateur attend au plus le délai de retour
normal avant d’abandonner la notification de réussite.

Les annulations explicites incrémentent un marqueur d’observation distinct
des commandes de charge. Une désactivation volontaire, erreur, restauration,
perte du secteur, arrêt de l’app ou absence d’état initial ne produit pas de
fausse réussite. Le retour de la protection avant affichage est revérifié.

Le détecteur prend aussi en charge les fins de décharge et d’étalonnage,
uniquement après une phase finale cohérente et un retour confirmé du secteur.
**Disponibilités après mise à jour avec `main` :** la décharge est disponible
(`BatteryCycle.dischargeAvailable`), tandis que l’étalonnage reste désactivé
(`BatteryCycle.calibrationAvailable`). Chaque notification respecte son propre
drapeau ; aucun cycle n’est réactivé par le code des alertes. La détection de
fin de décharge suit donc la disponibilité déjà décidée dans `main`. Les
transitions d’étalonnage sont testées sur des états synthétiques uniquement.
La notification de recharge ponctuelle est indépendante de ces drapeaux.

## Rappels, réglages et exécution

Réglages > Barre des menus propose trois interrupteurs et trois aperçus fictifs.
Les préfixes `additionalAlert.protection`, `additionalAlert.cpu` et
`additionalAlert.cycle` isolent les préférences `.enabled`, `.lastShown` et
`.snoozedUntil`. CPU et interruption : un rappel au maximum par 24 heures.
Chaque fin d’opération distincte peut être signalée ; son événement est consommé
après affichage. Les trois types proposent les reports d’une journée/semaine.
Les aperçus ne changent aucun rappel et ne pilotent aucune application/batterie.

Le contrôleur observe les états batterie toutes les cinq secondes, sans
déclencher de lecture ni de commande supplémentaire du helper. Les mesures
CPU arrivent du suivi déjà actif de la barre des menus. Les minuteries sont
suspendues en veille et arrêtées quand le suivi devient indisponible.
MacCare doit rester ouvert ; le système peut retarder les minuteries en
arrière-plan. Aucun mécanisme de maintien éveillé supplémentaire n’est ajouté.

Les alertes attendent la fin de la configuration et un moment où MacCare n’est
pas au premier plan, où aucun grand volet/alerte disque/mémoire n’est ouvert
et où le Smart Scan n’analyse ni ne nettoie. Priorité interne : interruption
batterie, fin d’opération, CPU. Une fin mise en attente expire après 30 minutes.

## Composants et validation

`AdditionalAlertsController`, `AdditionalAlertKind`, `AdditionalAlertReminder`,
`AdditionalAlertSettingsView`, `CPUAlertCondition`, `CPUAlertRanking`,
`CPUAlertView`, `BatteryAlertObservation`, `BatteryAlertDetector`,
`BatteryCompletionAlert` et `BatteryStatusAlertView` portent les ajouts.
Les intégrations concernent `BatteryModel`, `TrayPanelController`,
`TraySceneLifecycle`, `Shell` et `SettingsView`.

Validation initiale : 38 tests ciblés réussis, dont 14 tests de politiques/observations et
de clients batterie simulés, plus les régressions batterie, mémoire, disque
et disposition. La QA emploie un hôte indépendant et des exemples fictifs :
six captures (trois alertes dans deux apparences), commandes accessibles,
fermeture sans effet réel dans l’aperçu et action d’ouverture CPU vérifiées.
Preuves : `build/extended-alert-validation/`.

Limites : pas de campagne VoiceOver complète, pas de surcharge CPU artificielle,
pas de désactivation réelle de la protection et pas de cycle matériel. La copie
quotidienne et le paquet Dev déjà ouvert sont préservés ; le nouveau paquet
est assemblé séparément sous `build/extended-alerts/MacCare.app`.

Build Release et paquet Apple Development vérifiés le 6 novembre : signature
stricte, plist et `git diff --check` valides. La copie quotidienne 0.2.6 (8)
garde la même empreinte binaire. Les sept pages Outline concernées (index,
02, 03, 04, 06, 08 et 11) ont été mises à jour et relues ; leur emplacement
et leurs liens sont conservés.

Après mise à jour avec `main`, la suite complète passe : **212 XCTest et
226 tests Swift Testing**, ainsi que 94 tests Rust (deux tests ignorés),
15 tests de release, la frontière PowerUI sans écriture système et les
signatures Sparkle. Un test supplémentaire couvre les disponibilités finales :
décharge autorisée, étalonnage toujours désactivé. Les préférences des tests
d’alertes utilisent le dossier temporaire commun des tests.
