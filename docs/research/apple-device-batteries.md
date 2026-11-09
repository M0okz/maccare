# Batteries iPhone et Apple Watch depuis MacCare

Recherche du 9 novembre 2026. **Étude de faisabilité, non livrée**. Cette note
ne valide ni la disponibilité des appareils de Gregory ni leur consommation.
Aucune application, dépendance ou configuration de jumelage n'a été installée
ou modifiée pour cette recherche.

Suite locale : la variante native a été implémentée sans dépendance ajoutée
sur `codex/apple-device-batteries`, puis validée en USB pour l'iPhone et le
registre Watch avec les appareils de Gregory. Voir [le fonctionnement, les contrôles et
les limites matérielles actuelles](../apple-device-batteries.md). Les pistes
décrites plus bas restent des sources et propositions de l'étude initiale.

## Conclusion

Une application compagnon n'est pas une nécessité démontrée. Une première piste
concrète permet de lire la batterie de l'iPhone par USB ou Wi-Fi, puis celle de
sa Watch à travers le registre compagnon de l'iPhone. AirBattery utilise cette
méthode avec libimobiledevice. Sa documentation demande un iPhone ayant fait
confiance au Mac et ayant été relié au moins une fois en USB. L'utilisation
Wi-Fi dépend ensuite de sa visibilité sur le réseau local. Cela ne garantit
pas le fonctionnement sur chaque version iOS/watchOS actuelle.
[AirBattery, documentation de l'auteur](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/README.md).

La méthode exacte de Mole n'est pas établie dans cette note. Une capture
d'écran démontre une présentation, pas le protocole, ses prérequis ou son coût
énergétique. Le site de l'auteur distingue son application Mac fermée du CLI
ouvert : le CLI ne permet donc pas d'attribuer automatiquement une méthode à
l'application native. [Présentation de Mole par son auteur](https://mole.fit/).

## Sources macOS déjà utilisées

`TrayBatteryTelemetry.swift` lit `IOPSCopyPowerSourcesByType(4)` et interprète les
descriptions obtenues avec les accesseurs IOPS. Le repli HID lit `Product` et
`BatteryPercent`. Le contrôleur partagé effectue actuellement ces lectures
toutes les cinq secondes lorsque sa tâche de surveillance est active.
Références locales : `app/Sources/MacCare/TrayBatteryTelemetry.swift`,
`app/Sources/MacCare/TrayBatteryController.swift`.

Apple publie `IOPSCopyPowerSourcesByType`, les types d'accessoires et des
notifications de changement dans **IOPowerSourcesPrivate.h**. L'en-tête les
qualifie explicitement d'interfaces internes sans prise en charge publique.
Leur publication dans les sources ouvertes ne les transforme pas en contrat
SDK public. Des notifications d'ajout/retrait et de charge peuvent éviter une
nouvelle boucle de sondage, sous réserve de validation locale et de repli.
[En-tête Apple](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/ps.subproj/IOPowerSourcesPrivate.h).

Ce chemin local ne constitue pas un inventaire garanti de l'ensemble des
appareils Apple d'un compte. L'existence d'une icône iPhone dans le code MacCare
ne prouve pas qu'un iPhone donné publiera une source IOPS.

## iPhone sans application compagnon

`ideviceinfo` accepte les transports USB et réseau. Il interroge un domaine et
une clé avec `lockdownd_get_value`. Le domaine batterie figure dans son code.
Il peut fonctionner en connexion simple ; son mode normal réalise une poignée
de main susceptible d'inclure un jumelage. Un lecteur MacCare destiné aux seuls
appareils déjà approuvés doit contrôler ce comportement et ne pas déclencher
silencieusement une nouvelle association.
[Outil ideviceinfo](https://github.com/libimobiledevice/libimobiledevice/blob/fa0f79190142bc309307967c058f89c1b36eb6b8/tools/ideviceinfo.c),
[contrat de la poignée de main](https://libimobiledevice.org/docs/libimobiledevice/latest/lockdown_8h_a385f91866f3ca10755066f8fc8f79f44.html).

AirBattery lit `BatteryCurrentCapacity` et `BatteryIsCharging` dans
`com.apple.mobile.battery`. Sa voie iPhone ne nécessite pas d'écouter les logs
du téléphone. Sa lecture des logs concerne l'Apple Pencil optionnel. Il lance
aussi une commande `wificonnection ... true` lors d'une connexion USB : cette
mutation de configuration ne doit pas être reprise implicitement par MacCare.
[Implémentation AirBattery](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/IDeviceBattery.swift).

Cela prouve une implémentation existante du protocole, pas une API Apple publique
de surveillance à distance ni une compatibilité matérielle vérifiée ici.

## Variante native MobileDevice sans bibliothèque ajoutée

Le code de l'auteur d'ios-deploy contient `get_battery_level()` : connexion,
contrôle du jumelage, validation de celui-ci, ouverture de session,
`AMDeviceCopyValue` sur `com.apple.mobile.battery` / `BatteryCurrentCapacity`,
puis fermeture de session et déconnexion. Ce chemin fournit donc une preuve
d'usage de MobileDevice pour la batterie iPhone, sans dépendance obligatoire à
libimobiledevice. Le même fichier déclare et utilise `AMDeviceSecureStartService`
et des fonctions d'échange de messages de service, pour d'autres services.
[Code ios-deploy, lignes 1962–1975 et déclarations de service](https://github.com/ios-control/ios-deploy/blob/83f7d9ef97d03af42777965e80079f05332cc580/src/ios-deploy/ios-deploy.m).

**Hypothèse à tester :** ouvrir `com.apple.companion_proxy` avec ce transport
natif, puis échanger les deux requêtes décrites dans libimobiledevice. Le
protocole expose `GetDeviceRegistry` et `GetValueFromRegistry`, avec les clés
`GetValueGizmoUDIDKey` et `GetValueKeyKey`. Cette combinaison native n'a pas été
retrouvée dans un exemple exécuté ni testée ici.
[Implémentation du protocole compagnon](https://github.com/libimobiledevice/libimobiledevice/blob/fa0f79190142bc309307967c058f89c1b36eb6b8/src/companion_proxy.c).

Aucun contrat SDK Apple public correspondant n'a été trouvé. Il s'agit d'une
piste d'interface privée : symboles optionnels, disponibilité et ABI à vérifier
sur le macOS ciblé, arrêt propre si indisponibles, aucun appel de jumelage ou de
modification de préférence. Les fonctions illustrées ne donnent pas de délai
d'exécution borné dans leur signature ; un prototype doit aussi maîtriser
leur blocage éventuel avant toute intégration à la boucle de télémétrie.

## Apple Watch à travers l'iPhone

libimobiledevice expose `com.apple.companion_proxy`, l'énumération des appareils
associés et la récupération d'une valeur de leur registre. L'exemple `comptest`
de Nikias Bassen ouvre ce service sur l'iPhone et demande
`BatteryCurrentCapacity` et `BatteryIsCharging` pour ses montres. Il n'installe
pas d'application Watch dans cet exemple.
[Interface companion_proxy](https://github.com/libimobiledevice/libimobiledevice/blob/fa0f79190142bc309307967c058f89c1b36eb6b8/include/libimobiledevice/companion_proxy.h),
[exemple original comptest](https://gist.github.com/nikias/ebc6e975dc908f3741af0f789c5b1088).

**Limite de fraîcheur :** la requête vise un registre sur l'iPhone. Les sources
consultées ne donnent pas de délai garanti de mise à jour de la mesure Watch.
L'heure de réception dans MacCare ne doit donc pas être présentée comme l'heure
certaine d'une mesure effectuée sur la montre. Aucun test iPhone/Watch physique
n'a été fait pour cette note. Les erreurs, clés absentes et délais d'expiration
doivent rester des données indisponibles, jamais être convertis en zéro.

## Bluetooth et consommation

La voie BLE d'AirBattery est distincte : elle lance des recherches bornées,
connecte certains périphériques puis lit leurs caractéristiques. Sa documentation
limite la découverte iPhone via Bluetooth à l'iPhone et à l'iPad cellulaire et
indique que cette voie ne fournit pas la batterie Watch.
[Implémentation BLE](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/AirBattery/BatteryInfo/BLEBattery.swift),
[limites annoncées par l'auteur](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f933b862b2b6a9562a7f55e505e97/README.md).

Apple recommande de rechercher seulement lorsque nécessaire, d'arrêter la
recherche rapidement, de limiter les services lus et de préférer les
notifications aux sondages. Cela justifie d'éviter un scan Bluetooth permanent.
Cela ne fournit aucune mesure chiffrée du surcoût du futur lecteur MacCare.
[Guide énergétique Apple](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/BluetoothBestPractices.html).

## Variante avec applications compagnon

Les API publiques `UIDevice.batteryLevel` sur iPhone et
`WKInterfaceDevice.batteryLevel` sur Watch donnent leur propre charge si la
surveillance est activée ; une valeur inconnue vaut `-1`.
[UIDevice](https://developer.apple.com/documentation/uikit/uidevice/batterylevel),
[WKInterfaceDevice](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterylevel).

Watch Connectivity échange entre l'application Watch et son application iOS.
`updateApplicationContext` convient à un dernier état remplaçable et est envoyé
lorsque le système en a l'occasion ; cela ne garantit pas une fréquence fixe.
Le relais vers le Mac nécessite un autre transport et un choix d'architecture.
Cette variante ajoute installation, distribution et contraintes d'arrière-plan ;
elle doit faire l'objet d'une décision explicite avant implémentation.
[Exemple officiel Apple](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity),
[synchronisation de contexte](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)).

## Proposition pour une validation suivante

1. Vérifier en lecture seule si un iPhone déjà approuvé est disponible par USB
   ou réseau. Ne modifier ni la confiance, ni les préférences Wi-Fi, ni le Mac
   de production pour contourner une absence.
2. Faire une seule lecture batterie iPhone, puis une seule lecture du registre
   Watch, avec des délais bornés. Comparer aux affichages physiques.
3. Si cette voie fonctionne, prototyper une acquisition partagée : affichage
   ouvert seulement, au plus une requête par minute au départ, cache de dernier
   état connu, arrêt à la fermeture, retour arrière après échec, aucune boucle
   rapide de reconnexion. Ces durées sont une proposition à mesurer.
4. Mesurer le coût supplémentaire sur le Mac et observer le comportement des
   appareils avant d'affirmer que la fonctionnalité est peu énergivore. Séparer
   mesure locale CPU/réveils et consommation matérielle iPhone/Watch.

La dépendance et son packaging sont un choix à arrêter : le dépôt MacCare est
MIT, AirBattery affiche AGPL et les composants libimobiledevice ont leurs propres
licences. Cette recherche n'importe aucun code ou binaire AirBattery. Toute
réutilisation effective exige la vérification des notices et des obligations
des composants retenus, sans supposer que la licence du projet appelant couvre
ses dépendances.
