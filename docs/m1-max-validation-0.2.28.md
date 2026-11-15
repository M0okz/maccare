# MacCare Dev 0.2.28 — validation M1 Max

## Attention : deux paquets distincts portent le numéro 0.2.28

La version publique `v0.2.28`, publiée le 15 novembre à 09:15 (Paris), est basée
sur `3399a6e` (stabilité et activité en arrière-plan). Son code conserve le
message « macOS effectue ou prépare un étalonnage » et le refus général des
contrôles matériels. Elle ne contient ni le correctif de ce chantier ni son
mode d'essai M1 Max. Installer cette mise à jour standard ne livre donc pas ce patch.

Le paquet de cette page est **MacCare Dev 0.2.28 (9)**, issu de `12233bb`, fourni
uniquement dans l'archive locale `MacCare-0.2.28-m1-max-validation-arm64.zip`.
Il affiche « Prise en charge M1 Max en validation » sur MacBookPro18,4. Son nom,
son build et son origine doivent être vérifiés, pas seulement le numéro 0.2.28.
Cette distinction a été revérifiée dans l'archive signée et dans le tag public
après la capture transmise par Gregory. Aucun remplacement du Mac distant effectué.

## Préparation locale

15 novembre 2026. Base : MacCare 0.2.27 (`83099d7`), branche
`codex/m1-max-battery-diagnostics`. Paquet local **MacCare Dev 0.2.28 (9)**,
signé Developer ID, non notarié, sans flux de mise à jour. Aucun remplacement
de `/Applications/MacCare.app`, aucune publication, aucune activation distante.

## Changement

Le modèle observé `MacBookPro18,4` peut sélectionner la politique native avancée
dans une compilation dédiée. Les lectures root de CHIE, de la limite native
et de l'interface avancée sont confirmées par le diagnostic utilisateur.
Les méthodes SMC de charge refusées ne sont pas forcées.

Le choix est limité à ce modèle, au moyen de
`MACCARE_M1_MAX_BATTERY_TRIAL=1` lors du build. Cela ne modifie pas la liste des
modèles matériellement validés : `nativePolicyValidated` reste faux pour ce M1 Max.
Les builds ordinaires gardent le repli sur la limite native 80–100 %.

Le contrôleur existant gère les limites 50–100 %, le mode Voile et la pause
thermique lorsque la politique avancée est disponible. Il conserve ses exigences
de journal durable, d'adaptateur restaurable, de vérification de l'enregistrement,
de veille et de restauration après interruption. Une priorité de recharge Apple
active ou illisible bloque toujours les écritures. Le correctif ne remet aucun
signal Apple à zéro et ne force aucun accès SMC.

L'écran de protection et sa confirmation indiquent « en validation ». Le message
sur le refus de contrôle direct ne prétend plus que tous les accès matériels
sont indisponibles. Le message d'étalonnage est remplacé par celui de priorité de
recharge complète. L'interface est compilée et ses textes contrôlés dans le
paquet ; pas de campagne visuelle, clavier ou VoiceOver revendiquée.

## Construction et vérification

```sh
MACCARE_M1_MAX_BATTERY_TRIAL=1 bash app/build.sh
MACCARE_M1_MAX_BATTERY_TRIAL=1 MACCARE_VERSION=0.2.28 MACCARE_BUILD_NUMBER=9 \
  MACCARE_DEVELOPER_ID=1 MACCARE_SIGN_IDENTITY="IDENTITE_DEVELOPER_ID" \
  bash app/package.sh build/m1-max-validation/MacCare.app
```

Le helper expose `--battery-build-info` sans accès matériel, ainsi que les
diagnostics en lecture seule. Le diagnostic de compatibilité distingue le mode
de build (`nativePolicyTrialBuild`), l'éligibilité du modèle
(`nativePolicyActivationAllowed`) et la validation matérielle
(`nativePolicyValidated`). L'éligibilité ne contourne pas les autres garde-fous.

Le packaging inspecte le binaire compilé et refuse un mode différent de celui
demandé, ou une distribution publique d'un build d'essai. Ces deux refus ont été
testés avant assemblage. La CI inclut la compilation et le diagnostic du helper
d'essai ; elle n'a pas été exécutée à distance pour cette branche.

Vérifications locales : 174 tests batterie et 47 tests des modèles batterie de
l'application (25 XCTest, 22 Swift Testing) ; frontières C SMC et Objective-C
PowerUI sous ASan/UBSan ; garde de lecture seule du CLI ; 19 tests de packaging ;
contrôle sans dépendance à des outils développeur au runtime. Le scénario simulé
M1 Max passe par la sélection réelle de backend, le journal, CHIE simulé, le
maintien, la reprise et la restauration. Priorité Apple active/inconnue : zéro
écriture de politique ou d'adaptateur. Ces simulations ne valident pas le matériel.

Le paquet est vérifié : version 0.2.28 (9), nom MacCare Dev, mode d'essai actif,
signature stricte valide, métadonnées du helper cohérentes, absence de flux
Sparkle. Le diagnostic du helper signé est exécuté sans privilèges sur le M1
local. Les empreintes des exécutables de l'app utilisateur sont inchangées.

## Essais matériels restant à autoriser

La consigne utilisateur reste la lecture seule sur le M1 Max. Avant toute
installation du helper ou activation, demander l'accord pour une campagne
réversible :

1. Vérifier la présence secteur, l'absence de contrôleur concurrent et la levée
   naturelle de la priorité Apple. Si elle reste active, aucun essai d'écriture.
2. Relever les réglages initiaux, puis essayer une limite à 80 % via le contrôleur
   et son journal de restauration ; observer la charge réelle, pas seulement
   l'enregistrement de la limite.
3. Vérifier maintien puis reprise (par exemple une plage 75–80 %), sans décharge
   forcée. Observer la stabilité de l'alimentation secteur.
4. Vérifier désactivation, veille et restauration des réglages initiaux, puis
   récupération après interruption dans une étape contrôlée séparée.
5. N'étendre la liste validée et ne préparer la publication stable qu'après des
   observations matérielles réussies et documentées.

La nouvelle version prépare ces essais ; elle ne prétend pas déjà les avoir
réalisés. Documentation Outline à synchroniser : accès prévu toujours en échec
`Bitwarden status failed`, voir `outline-sync-pending-m1-max-battery.md`.
