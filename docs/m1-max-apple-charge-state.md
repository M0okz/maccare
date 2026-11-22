# M1 Max : demande Apple et activation — développement du 22 novembre 2026

État : **publié dans MacCare 0.2.30 (32) le 22 novembre 2026**, après la
[PR #39](https://github.com/M0okz/maccare/pull/39). Le développement local décrit
ci-dessous a été vérifié avant publication. MacBookPro18,4 reste un modèle en
validation : cette correction ne démontre pas le maintien physique d’une limite,
sa reprise après veille ou la restauration matérielle.
[Preuves de livraison publique](release-integration-0.2.30.md).

## Problème et comportement

Le diagnostic fourni sur le M1 Max montre une demande Apple de recharge complète
active hors secteur, alors qu’aucune limite native n’est enregistrée. La présence
de l’interface native et l’éligibilité du modèle ne suffisent pas à autoriser
l’activation. La 0.2.29 ne remontait ce refus qu’après une tentative d’activation ;
son erreur pouvait rester mémorisée après disparition du signal.

L’assistant expose maintenant `appleFullChargeOverride` dans son statut :
`active`, `inactive` ou `unknown`. Un ancien assistant peut omettre ce champ ;
le décodage reste compatible et les gardes matériels restent décisifs.
Pour une méthode native inactive, l’écran explique une demande Apple active ou
illisible avant l’activation. Le bouton **Actualiser l’état Apple** relit le statut,
sans activer la protection. Les commandes d’activation du modèle respectent aussi
cet état, y compris les automatisations. Une reprise déjà tentée n’est pas mise
en attente pour un démarrage automatique à la disparition du signal.

L’assistant peut retirer une ancienne erreur de préactivation Apple uniquement
après un signal explicitement inactif et une lecture matérielle réussie, sans
session ni restauration en cours. Les autres erreurs sont conservées. Aucun
texte localisé n’est utilisé pour décider qu’une erreur est périmée.

## Diagnostic complet en lecture seule

L’option existante du nouveau helper reste :

```sh
sudo /chemin/vers/le/nouveau/MacCareHelper --battery-full-diagnostics
```

La matrice des 40 lectures SMC, dont CHIE, et `compatibility.fullChargeOverride`
sont conservées. Le nouveau bloc `appleGauging` lit uniquement le fichier
`/private/var/root/Library/Preferences/com.apple.powerd.batterygauging.plist` :

- dates UTC enregistrées de dernier contrôle et dernière recharge complète ;
- `lastFullChargeReq`, distinct du signal Apple actuel ;
- dates DOD0, QMax et QualQMax de chaque pack, sans numéro de série ;
- `readState` : `available`, `unavailable`, `invalidFormat` ou `tooLarge`.

La lecture est limitée à 64 Kio et 16 packs. Seuls des champs connus et typés
sont sérialisés. Les dates futures restent des valeurs enregistrées, sans en
déduire une autorisation ou un étalonnage terminé. Une lecture indisponible n’est
jamais transformée en demande inactive. Cette lecture a lieu sur demande de
diagnostic, pas dans la boucle de contrôle ni à chaque rafraîchissement de l’écran.

## Limites et origine des observations

Le suivi Apple n’est ni supprimé, ni réécrit, ni antidaté. Aucun signal n’est
forcé et aucun garde de charge n’est contourné. La procédure de réinitialisation
précédemment fournie n’a pas été exécutée dans cette intervention ; son résultat
sur le M1 Max n’a pas été communiqué.

Le [suivi mainteneur AlDente #1846](https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/issues/1846)
décrit également une demande persistante et un retour possible après une remise
à zéro du suivi. Cela étaye la nécessité de distinguer les données enregistrées
du signal actuel ; ce n’est pas une validation du contrôleur MacCare ni une
preuve de défaut de la batterie remplacée.

La validation matérielle nécessite encore un nouveau relevé sur le M1 Max,
puis un essai explicitement autorisé lorsque la demande Apple est inactive.
Les essais de cette intervention utilisent des pilotes simulés ou le diagnostic
en lecture seule du helper de développement. La copie de production n’est pas
utilisée pour les essais.

## Vérifications et paquet local

- Test reproduisant l’absence d’état Apple avant activation : échec observé
  avant correction, réussite après correction.
- 111 tests ciblés réussis ; suite complète ensuite : 378 XCTest dont 7 ignorés,
  et 293 Swift Testing, sans échec (664 réussites).
- Pont PowerUI sous ASan/UBSan : réussi, aucun setter natif invoqué.
- Diagnostics CLI des helpers Debug et Release : réussis avec garde contre les
  effets de bord, 40 lectures SMC dont les quatre tentatives CHIE.
- Compilation Release arm64 réussie. Des avertissements de concurrence existants
  restent présents ; aucune validation Swift 6 stricte supplémentaire revendiquée.
- Paquet local `build/m1-max-apple-state/MacCare.app` : **MacCare Dev 0.2.30 (32)**,
  signature Apple Development vérifiée, essai M1 Max activé, aucun flux Sparkle.
  Le helper empaqueté produit le diagnostic complet en lecture seule. Sans
  privilèges, `appleGauging.readState` vaut `unavailable`, conformément aux droits
  du fichier root. Le parsing avec données typées est testé sur fixtures.

Les preuves locales sont les fichiers `build/m1-max-state-*-tests.log`,
`build/m1-max-state-build.log`, `build/m1-max-state-package.log` et
`build/m1-max-state-package-validation.json`. Le paquet Dev n’a pas été lancé dans
l’interface graphique, installé ou publié. L’interface et VoiceOver restent à
valider visuellement ; la compilation et les tests du modèle ne les remplacent pas.
Le paquet distribué 0.2.30 (32) est distinct de ce paquet Dev ; ses contrôles figurent dans le bilan de livraison.

La synchronisation Outline est en attente après échec de l’accès prescrit :
[note de reprise](outline-sync-pending-m1-max-battery.md).
