# Installateur MacCare

Le parcours est celui d’un DMG macOS : deux éléments natifs, `MacCare.app` et un lien symbolique
`Applications` vers `/Applications`. L’utilisateur glisse le premier sur le second, puis lance
MacCare depuis Applications. Aucun assistant système n’est installé ni activé par le DMG.

## Construction

Prérequis sur le Mac de construction : outils Swift/Rust du projet, Python 3.11+, `pip` et les
outils macOS `hdiutil`, `iconutil`, `codesign`, `lipo` et `ditto`.

```sh
./app/create-dmg.sh
./app/create-dmg.sh --skip-build
./app/create-dmg.sh --skip-build --output build/MacCare-local.dmg
```

Le script réutilise `app/build.sh` et `app/package.sh`. Ce dernier accepte maintenant un chemin
de sortie explicite sous `build/`, ce qui évite de remplacer l’app actuellement ouverte lors
de la préparation du DMG. Sans argument, sa sortie reste `build/MacCare.app`.

La construction des métadonnées Finder utilise [dmgbuild 1.6.7](https://dmgbuild.readthedocs.io/en/latest/settings.html),
épinglé dans `requirements.txt`. Il est installé depuis PyPI dans un environnement Python temporaire,
supprimé avec les fichiers de montage et de copie à la fin de la construction. Aucun paquet Python
n’est installé globalement et aucune automatisation AppleScript du Finder n’est utilisée.

Les sorties durables sont le DMG, son fichier `.sha256` et les visuels générés sous
`build/installer-assets/`. Les répertoires de travail `.installer-*` sont nettoyés. En cas d’échec
exceptionnel de démontage, le script conserve seulement le répertoire encore monté et affiche son chemin.

## Visuels et disposition

`render-assets.swift` dessine une icône originale (coche blanche et carré arrondi violet),
toutes les tailles requises par `iconutil`, et un fond TIFF 1×/2×. L’app indique cette icône
avec `CFBundleIconFile`, avant d’être signée. Les visuels sont originaux ; la capture fournie
sert uniquement de référence au parcours glisser-déposer.

Le canevas mesure 680 × 460 points ; la fenêtre réserve 530 points de hauteur pour laisser
les barres Finder visibles selon les préférences du Mac sans rogner le texte. Les deux icônes
mesurent 112 points et sont centrées en (190, 235) et (490, 235). La flèche est dessinée dans le
fond ; l’app et Applications sont de vrais éléments que le Finder peut manipuler.

## Contrôles effectués

1. Signature du paquet et de son assistant vérifiée avant création de l’image.
2. Image montée en lecture seule ; signature du paquet embarqué et présence de l’icône,
   de l’assistant et du lien exact vers `/Applications` vérifiées.
3. Positions des icônes, taille et type de fond relus dans le vrai `.DS_Store` de l’image.
4. App copiée avec `ditto` dans un dossier temporaire isolé ; signature vérifiée après copie.
5. Ouverture réelle du DMG dans le Finder : fond, icônes, flèche et texte de bas de page contrôlés
   avec les barres d’onglets et d’état du Mac conservées.

Aucune installation réelle dans `/Applications`, aucune modification de l’app déjà ouverte et
aucun nouveau consentement système pendant ces contrôles. La copie de test n’a pas été lancée.

### Régression de signature évitée

L’option `hide_extensions` de dmgbuild appelle `SetFile` après avoir copié le paquet signé.
Cela ajoutait `FinderInfo` à `MacCare.app` et le contrôle strict échouait avec
`resource fork, Finder information, or similar detritus not allowed`. L’extension reste donc
visible et le paquet signé n’est plus modifié après signature. Le contrôle à l’intérieur du
DMG fait échouer la construction si cette régression revient.

## Distribution

Le paquet actuel est signé avec l’identité Apple Development existante. Le DMG de travail
est un artefact local, non notarié ; ce n’est pas une livraison publique. Developer ID,
runtime durci de l’app avec son autorisation d’Automatisation, notarisation et validation du
ticket restent les étapes de distribution prévues par la feuille de route. Le fichier généré
ici cible arm64 ; son nom reprend l’architecture du binaire réellement embarqué.
