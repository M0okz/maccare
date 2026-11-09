# Batteries des appareils jumelés

État du 9 novembre 2026 : **développement local non livré**, branche
`codex/apple-device-batteries`, issue de `258db00`. La présence du lecteur dans
le code ne valide pas encore la lecture d'un iPhone ou d'une Watch physiques.
La copie quotidienne `/Applications/MacCare.app` n'est pas remplacée.

## Fonctionnement et préparation

MacCare conserve ses lectures IOKit/HID pour les accessoires que macOS expose.
Une sonde utilisateur native, `MacCareDeviceBatteryProbe`, complète ces données
pour les iPhone et iPad déjà jumelés. Elle lit le nom, la classe, l'identifiant
local et le niveau de batterie ; l'identifiant est haché avant de sortir de la
sonde. Pour une Watch associée, elle essaie le registre compagnon de l'iPhone.

1. Brancher l'iPhone/iPad en USB, le déverrouiller et accepter la confiance
   dans le Finder et sur l'appareil.
2. Pour un accès ultérieur sans câble, activer explicitement dans le Finder
   « Afficher cet iPhone lorsqu'il est connecté au Wi-Fi », puis appliquer.
   L'appareil doit ensuite être joignable sur le réseau local. MacCare
   n'active pas cette option à la place de la personne.
3. Ouvrir l'accueil ou le volet de la barre des menus. Une tentative infructueuse
   est espacée de cinq minutes ; relancer la Dev permet une tentative immédiate
   pendant la validation.

L'interface privée MobileDevice fournie par macOS est chargée optionnellement.
La sonde est un processus séparé pour contenir une erreur ou un blocage de cette
interface. Ce n'est ni le service privilégié ni un démon permanent. Aucun code
ou binaire AirBattery/libimobiledevice, aucune dépendance ajoutée ni application
iOS/watchOS n'est embarqué. Aucun scan Bluetooth ou flux de journaux n'est lancé.

Les échanges sont limités à `AMDeviceCopyValue` et aux requêtes
`GetDeviceRegistry` / `GetValueFromRegistry` du service compagnon. Aucun appel
de jumelage, d'installation, de modification des préférences Wi-Fi ou de
contrôle de charge. Les sessions sont ouvertes uniquement après validation
d'un jumelage existant, puis fermées. Une erreur devient une absence de valeur.

## Budget de travail et affichage

- Acquisition partagée entre accueil et volet : aucune double session.
- Aucune nouvelle minuterie : les tâches des cartes visibles sollicitent le
  lecteur, puis sont annulées lorsque leurs vues sont démontées.
- Succès : une tentative au plus par minute, ou toutes les deux minutes en
  mode économie d'énergie. Sans appareil, après erreur ou réponse partielle :
  cinq minutes entre tentatives.
- Arrêt de la sonde après quatre secondes, seconde limite de cinq secondes
  dans le parent. Une lecture déjà lancée peut finir dans ce délai après
  fermeture de la vue ; aucun nouveau relevé n'est alors lancé.
- Cache uniquement en mémoire. Expiration après trois minutes, plus la
  tolérance existante de vingt secondes de l'historique d'affichage. Une
  absence n'est jamais convertie en zéro.

Les cartes compactes privilégient téléphone/iPad, Watch, puis écouteurs ; le
détail conserve tous les accessoires, boîtier compris. Les infobulles et les
valeurs d'accessibilité précisent le dernier niveau connu et son heure de
réception. Pour la Watch : **dernier niveau connu par l'iPhone**. L'heure de
réception ne prétend pas être l'heure de la mesure effectuée sur la montre.

## Validation et limites

Le premier sondage natif sans appareil joignable a terminé sans erreur en
1,005 s, dont 0,0609 s de CPU du processus enfant, sans sortie d'erreur. Cette
observation ne mesure ni le travail des démons macOS, ni les échanges/réveils du
téléphone, ni la consommation de sa Watch. Elle ne suffit pas à qualifier le
coût énergétique de la fonction complète.

Les scénarios simulés vérifient les barrières de confiance, les fermetures de
session, les requêtes autorisées, les données incohérentes ou inconnues, la
conservation d'un résultat iPhone si la Watch échoue, l'espacement, la concurrence,
l'expiration et la provenance. Ces fixtures ne valident ni l'ABI privée avec
appareil connecté, ni les réponses d'un iPhone réel.

Contrôles locaux réussis : **24 tests Swift ciblés**, **19 tests Python de
packaging**, fixtures natives sous ASan/UBSan, build Release arm64, signature
profonde stricte du paquet Dev et de sa sonde avec runtime durci. Le test de
blocage conserve la réponse iPhone déjà reçue et arrête le lecteur après
5,129 s. Le paquet `build/apple-device-batteries/MacCare.app` est une Dev
0.2.16 (19), sans flux Sparkle ; il s'est ouvert sur l'accueil, dont l'arbre
d'accessibilité affiche les mesures réelles du Mac, sans appareil mobile
inventé. Aucun parcours complet VoiceOver/clavier n'est revendiqué.

La sonde du paquet signé a aussi terminé sans appareil en 1,509 s, dont
0,0495 s de CPU. Les deux sondages suivant le branchement annoncé par Gregory
n'ont pas reçu de résultat mobile ; le MacBook Pro M1/8 Go de l'agent ne voit
pas encore de produit USB iPhone. La correspondance entre le Mac où le câble
est branché et ce Mac de test reste à confirmer.

Les exécutables installés sont restés identiques : quotidienne
`78763818d09076720974baaa3d915c29728d37362f385ffd3615a8a645104133`, Dev
`c44547b0908efcfc569766d5b45b4c16673111a6e42602861dbd78cecdbd2d57`.
Preuves locales : `build/apple-device-batteries-qa/validation.json`,
`usb-probe.json`, `build/apple-device-battery-{tests,deadline-tests,package}.log`.

```sh
bash app/Tests/DeviceBatteryProbeTests/run.sh
swift test --package-path app --build-system swiftbuild --arch arm64 -c release \
  -Xlinker -L"$PWD/core/target/release" \
  --filter 'MobileDeviceBatteryTests|TrayBatteryControllerTests|TrayBatteryTelemetryTests'
```

**Reste à vérifier sur matériel** : USB, Wi-Fi après débranchement, niveaux
comparés aux appareils, fraîcheur Watch, téléphone verrouillé, perte/rétablissement
réseau et consommation avec appareils connectés. Aucun de ces contrôles n'est
déclaré réussi à ce stade. Voir [la recherche et ses sources primaires](research/apple-device-batteries.md).

## Composants

`MacCareDeviceBatteryProbe/main.m` isole l'ABI. `MobileDeviceBatteryReader`
valide le flux JSON borné et lance la sonde hors de l'exécuteur coopératif.
`MobileDeviceBatteryStore` partage l'acquisition et le cache. Le sampler
fusionne les sources ; `TrayBatteryAccessoryHistory` conserve la provenance et
distingue deux appareils mobiles de même nom. Le packaging signe la sonde
séparément, puis le paquet ; la distribution contrôle aussi son architecture.
La CI exécute les fixtures natives sous ASan/UBSan.
