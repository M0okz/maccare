# Reconnaître un build de développement

Les paquets assemblés par `app/package.sh` affichent **MacCare Dev** dans la
fenêtre principale et comme nom d’application macOS. Ce repère reste visible
pendant la navigation, y compris lorsque la barre latérale est réduite.

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
