# Reconnaître un build de développement

Les paquets assemblés par `app/package.sh` affichent **MacCare Dev** dans la
fenêtre principale et comme nom d’application macOS. Ce repère reste visible
pendant la navigation, sous les boutons de la fenêtre : « Dev » seul lorsque la
barre latérale est réduite.

Le packaging écrit le booléen `MacCareDevelopmentBuild` dans `Info.plist`, avant
signature. Il est vrai par défaut et faux avec `MACCARE_DISTRIBUTION=1` : les
distributions conservent le nom **MacCare**, sans repère Dev. Le rôle ne dépend
pas de `DEBUG`, les builds locaux étant également optimisés en Release. Un
exécutable lancé sans métadonnées de paquet se présente comme un build Dev.

Ce libellé facilite l’identification ; il ne crée pas d’isolation entre les
préférences, les consentements ou le service privilégié. Le bundle ID reste
`org.maccare.app`. Toujours vérifier le chemin exact avant une intervention et
préserver la copie utilisateur dans `/Applications/MacCare.app` lors du
développement. Un ancien paquet conserve son ancien affichage jusqu’à sa
reconstruction ; aucune installation utilisateur n’est nécessaire pour tester
le nouveau repère.

## Volet compact — développement du 6 novembre 2026

Le paquet `build/tray-layout/MacCare.app` permet de vérifier le volet
compact et la présence dans le Dock à la fermeture/réouverture d’une fenêtre.
Il affiche MacCare Dev et ne remplace pas la copie dans Applications.
Voir [la disposition, les contrôles et les limites](menu-bar-panel.md).

Ce paquet inclut aussi la grille de stockage, la pression mémoire, la température
CPU et le réseau actif/IP/Mb/s. Pour sa QA, le lancement utilise
`-battery.protection.resume NO` et ne reprend pas la protection de charge.

La dernière passe ajoute un indice de santé explicable et l’en-tête RAM/stockage/
macOS/uptime, ainsi que la carte batterie enrichie et ses relevés en lecture seule.

La passe suivante simplifie l’en-tête (caractéristiques et uptime sur une ligne,
score chiffré réservé au détail), ajoute GPU et ventilateurs en lecture seule,
et configure jusqu’à quatre raccourcis dans Réglages → Menu. Le volet mesure
420 × 590 points au maximum. Plus et Quitter sont retirés de son pied ; ouvrir
MacCare et Réglages utilisent des icônes nommées. 53 tests ciblés et neuf
assertions C de décodage réussis ; rendu natif du volet et réglages blancs vérifiés.
État local non livré, `main` à `134b7bc` plus modifications de travail.
