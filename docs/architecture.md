# Architecture de MacCare

## Application et moteur

L’application SwiftUI conserve les modèles de chaque rubrique dans `AppState`.
Le moteur Rust expose une frontière C dans `core/include/maccare_core.h` ; Swift
utilise le module `CMacCareCore`. Les règles TOML ouvertes sont livrées dans les
ressources du paquet. Les recherches de fichiers et les suppressions sont des
opérations distinctes : un résultat d’analyse ne vaut pas autorisation de supprimer.

Le moteur prépare un plan puis revalide les éléments avant action : identité du
fichier, liens symboliques, confinement sous la racine, arbres protégés. Les tests
Rust couvrent ces contrôles et les modifications concurrentes du système de fichiers.

## Assistant privilégié

`MacCareHelper` est embarqué dans `Contents/MacOS`. Son plist launchd déclare un
`BundleProgram` relatif au paquet. SMAppService gère son enregistrement, sous
approbation explicite de l’utilisateur. Le DMG n’enregistre rien dans le système.

Le protocole XPC décrit des opérations fermées ; ce n’est pas une interface shell
arbitraire. L’assistant contrôle la signature du client et applique les contrôles
propres à chaque opération. Les opérations sensibles sont séparées de l’analyse
et des préférences d’inclusion dans un scan.

## Batterie et télémétrie

La télémétrie utilise les interfaces macOS et distingue les données indisponibles
des valeurs nulles. Le suivi CPU, mémoire et Wi-Fi est partagé entre la barre des
menus, l’accueil et les fenêtres de détails. Chaque consommateur enregistre sa
demande de suivi ; la disparition de l’un ne doit pas arrêter les autres.

La protection batterie est facultative et démarre désactivée. L’assistant conserve
un état de récupération et un bail surveillé ; il tente de restaurer la configuration
initiale à l’arrêt, à la veille ou à la perte de contact. Le backend dépend du Mac
et de la disponibilité des interfaces de charge. Les détails mesurés sur une
machine ne constituent pas une validation matérielle de tous les modèles.

## Distribution

L’app et l’assistant conservent des identifiants distincts, avec une signature Apple
cohérente. Le paquet de distribution utilise le runtime durci ; l’app déclare son
entitlement d’Automatisation pour System Events. Sparkle est embarqué dans Frameworks
et ses composants imbriqués sont signés avant l’app.

Sparkle vérifie un flux public signé et la signature du DMG final avant extraction.
Les recherches automatiques sont désactivables et les installations nécessitent
une action de l’utilisateur. Les détails et limites de validation sont dans
[la procédure de release](releasing.md).
