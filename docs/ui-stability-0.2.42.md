# MacCare 0.2.42 DEV · Stabilité de l’interface

24 novembre 2026 · Build 44 arm64 · Branche locale `codex/ui-stability` · Code `8b0302e` · Référence produit 0.2.41 (`78a922a9dd9f`).

## Résultats

489 transitions chronométrées sur 132 parcours distincts de la candidate. Un parcours désigne une navigation précise. Une fenêtre ouverte depuis le volet et la même page ouverte depuis la barre latérale comptent donc séparément. Les mesures de rendu et de lancement sont comptées à part.

Sur cinq lancements successifs du processus DEV, les commandes de l’accueil étaient présentes et actives après **762 ms en médiane**, avec des valeurs de 734 à 986 ms. La référence 0.2.41 donnait 998 ms sur trois lancements (788–1359 ms). Les caches du système sont conservés.

Le volet et l’accueil sont restés ouverts ensemble pendant **63,7 secondes**. Les rectangles des deux fenêtres, les commandes suivies de l’accueil et les deux boutons du bas du volet sont restés à la même position sur les 101 relevés.

## Navigation principale dans les mêmes conditions

Même machine, même dossier d’essai, fenêtre 1 211 × 773 points et même ordre d’actions. Deux sessions DEV par version, chacune composée de deux passages. Les sessions ont alterné dans l’ordre 0.2.41, 0.2.42, 0.2.42, puis 0.2.41. Les valeurs sont en millisecondes.

| Navigation | Médiane 0.2.41 | Médiane 0.2.42 | Étendue 0.2.42 | Essais 0.2.42 |
| --- | --- | --- | --- | --- |
| Accueil | 196 | 200 | 130–263 | 4 |
| Nettoyage | 114 | 118 | 58–200 | 4 |
| Performances | 104 | 108 | 47–174 | 4 |
| Batterie | 132 | 136 | 78–192 | 4 |
| Applications | 107 | 107 | 47–162 | 4 |
| Mes fichiers | 114 | 116 | 58–178 | 4 |
| Espace disque | 114 | 114 | 56–176 | 4 |
| À propos | 112 | 113 | 52–180 | 4 |
| Réglages · ouverture | 538 | 401 | 295–509 | 4 |
| Réglages · Analyse | 392 | 187 | 151–213 | 4 |
| Réglages · Performances | 338 | 162 | 158–162 | 4 |
| Réglages · Fichiers et disque | 391 | 204 | 185–224 | 4 |
| Réglages · Planification | 361 | 172 | 165–183 | 4 |
| Réglages · Menu | 584 | 309 | 288–320 | 4 |
| Réglages · Suppression | 358 | 169 | 167–186 | 4 |
| Réglages · Exclusions | 340 | 154 | 153–158 | 4 |
| Réglages · Général | 474 | 421 | 415–424 | 4 |
| Volet de menus | 738 | 282 | 109–483 | 4 |
| Volet → accueil | 271 | 272 | 271–296 | 4 |

Sur les changements d’onglet des Réglages, la médiane de cette série est passée de 410 à 182 ms. Dans les sessions standard plus longues, elle était respectivement de 400 et 156 ms. Les deux séries sont détaillées séparément pour conserver l’effet de l’état de la session.

## Temps par écran et par sous-écran

Les valeurs sont en millisecondes. La colonne DEV correspond à la médiane du début de stabilité des commandes. La dernière colonne donne la médiane de stabilisation visuelle pour les parcours également filmés par échantillonnage dans l’aperçu compact. Un tiret indique une mesure indisponible ou un protocole de référence différent.

### Rubriques

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Accueil | standard | 186 | 241 | 125–249 | 5 | 752 |
| Nettoyage | standard | 107 | 175 | 61–179 | 5 | 226 |
| Performances | standard | 85 | 149 | 65–152 | 5 | 202 |
| Batterie | standard | 110 | 179 | 101–184 | 5 | 252 |
| Applications | standard | 151 | 195 | 61–227 | 5 | 261 |
| Mes fichiers | standard | 101 | 172 | 65–190 | 5 | 222 |
| Espace disque | standard | 89 | 161 | 65–163 | 5 | 223 |
| Mes outils | standard | 117 | 182 | 90–198 | 5 | 258 |
| À propos | standard | 91 | 161 | 50–172 | 5 | 260 |

### Nettoyage

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Nettoyage · bilan | standard | — | 70 | mesure unique | 1 | 98 |
| Nettoyage · catégories | standard | 250 | 216 | 113–218 | 5 | 266 |
| Nettoyage · Résultats de l’analyse | standard | 395 | 317 | 234–321 | 5 | 210 |
| Nettoyage · Corbeilles | standard | 387 | 360 | 268–369 | 5 | 229 |
| Nettoyage · Système | standard | 515 | 438 | 238–473 | 5 | 356 |
| Nettoyage · Développement | standard | 378 | 356 | 224–365 | 5 | 198 |
| Nettoyage · Simulateurs | standard | — | 525 | 232–545 | 5 | 324 |
| Nettoyage · Par catégorie | standard | 464 | 390 | 248–402 | 5 | 270 |
| Nettoyage · bilan après analyse | données d’essai | — | 282 | mesure unique | 1 | — |

### Batterie

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Batterie · Protection de la batterie | standard | 239 | 99 | 96–136 | 5 | 299 |
| Batterie · Profils d’utilisation | standard | 226 | 93 | 85–117 | 5 | 312 |
| Batterie · Décharge contrôlée | standard | 204 | 77 | 66–80 | 5 | 257 |
| Batterie · Programmations | standard | 289 | 147 | 134–154 | 5 | 316 |
| Batterie · Historique | standard | 261 | 137 | 126–183 | 5 | 294 |
| Batterie · Appareils Apple | standard | 202 | 72 | 59–79 | 5 | 574 |

### Performances et entretien

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Performances · entretien | standard | 201 | 335 | 241–385 | 5 | 428 |
| Performances · Éléments d’ouverture | standard | 365 | 390 | 285–433 | 5 | 489 |
| Performances · Éléments d’arrière-plan | standard | 347 | 389 | 297–416 | 5 | 538 |
| Entretien · Optimiser Mail | données d’essai | 36 | 53 | mesure unique | 1 | — |
| Entretien · Réindexer Spotlight | données d’essai | 45 | 35 | mesure unique | 1 | — |
| Entretien · Autorisations du compte | données d’essai | 36 | 33 | mesure unique | 1 | — |
| Entretien · Vider le cache DNS | données d’essai | 31 | 32 | mesure unique | 1 | — |
| Entretien · Libérer l’espace purgeable | données d’essai | 41 | 33 | mesure unique | 1 | — |
| Entretien · Rétablir les aperçus des fichiers | données d’essai | — | 68 | mesure unique | 1 | — |
| Entretien · Corriger l’affichage des polices | données d’essai | — | 57 | mesure unique | 1 | — |
| Entretien · Corriger le menu « Ouvrir avec » | données d’essai | — | 30 | mesure unique | 1 | — |
| Entretien · confirmation | données d’essai | — | 385 | mesure unique | 1 | — |
| Performances · bilan | données d’essai | — | 180 | mesure unique | 1 | — |

### Mes fichiers et disque

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Fichiers · bilan | standard | — | 58 | mesure unique | 1 | 89 |
| Fichiers · Doublons | standard | 125 | 184 | 84–191 | 5 | 258 |
| Fichiers · Gros fichiers | standard | 144 | 212 | 105–224 | 5 | 261 |
| Fichiers · Images PNG | standard | 107 | 188 | 63–190 | 5 | 255 |
| Disque · Liste | données d’essai | 120 | 136 | mesure unique | 1 | — |
| Disque · Évolution | données d’essai | 119 | 146 | mesure unique | 1 | — |
| Disque · Carte | données d’essai | 121 | 133 | mesure unique | 1 | — |
| Disque · dossier | données d’essai | 113 | 99 | mesure unique | 1 | — |

### Accueil et accès rapide

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Accès rapide | standard | 286 | 288 | 267–302 | 5 | 252 |
| Accueil · détail du processus | standard | 549 | 538 | 533–573 | 3 | — |
| Accueil · indice santé | données d’essai | 246 | 231 | mesure unique | 1 | — |
| Accueil · autorisations | données d’essai | 56 | 62 | mesure unique | 1 | — |
| Accès direct · Mises à jour | données d’essai | — | 91 | mesure unique | 1 | — |
| Accès direct · Désinstalleur | données d’essai | — | 238 | mesure unique | 1 | — |
| Accès direct · Espace disque | données d’essai | — | 91 | mesure unique | 1 | — |
| Accès direct · Maintenance | données d’essai | — | 81 | mesure unique | 1 | — |
| Accueil · tuile Batterie | données d’essai | — | 193 | mesure unique | 1 | — |
| Accueil · tuile disque | données d’essai | — | 171 | mesure unique | 1 | — |

### Outils

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Outils · nettoyage d’écran | standard | 307 | 403 | 273–414 | 5 | 314 |
| Outils · Santé des disques | standard | 208 | 170 | 70–177 | 5 | 707 |
| Outils · Mode nettoyage d’écran | standard | 235 | 182 | 82–184 | 5 | 265 |
| Outils · Fichiers IA inutiles | standard | 267 | 257 | 137–307 | 5 | 260 |
| Outils · Autorisations des applications | standard | 245 | 196 | 100–199 | 5 | 235 |
| Outils · Réparer l’affichage | standard | 189 | 172 | 78–173 | 5 | 268 |
| Outils · Gérer le démarrage | standard | 287 | 231 | 125–246 | 5 | 310 |
| Outils · Caches et données locales | standard | 231 | 182 | 69–185 | 5 | 257 |

### Applications

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Applications · Installées | standard | 195 | 233 | 173–267 | 5 | 443 |
| Applications · Mises à jour | standard | 350 | 408 | 173–434 | 5 | 522 |
| Applications · Résidus | standard | 193 | 255 | 154–263 | 5 | 372 |
| Applications · Démarrage | standard | 175 | 231 | 131–251 | 5 | 388 |
| Applications · Applications peu utilisées | standard | 249 | 210 | 206–215 | 3 | — |
| Applications · Fichiers d’installation | standard | 264 | 227 | 221–244 | 3 | — |
| Applications · bilan | données d’essai | — | 176 | mesure unique | 1 | — |
| Applications · Applications incompatibles | données d’essai | 212 | 196 | 187–200 | 3 | — |

### Réglages

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Réglages · ouverture | standard | 309 | 283 | 275–484 | 5 | 680 |
| Réglages · Analyse | standard | 389 | 192 | 139–200 | 5 | 189 |
| Réglages · Performances | standard | 325 | 147 | 119–154 | 5 | 181 |
| Réglages · Fichiers et disque | standard | 372 | 182 | 126–187 | 5 | 182 |
| Réglages · Planification | standard | 326 | 155 | 125–157 | 5 | 177 |
| Réglages · Menu | standard | 558 | 289 | 285–302 | 5 | 288 |
| Réglages · Suppression | standard | 328 | 152 | 146–155 | 5 | 180 |
| Réglages · Exclusions | standard | 318 | 146 | 140–156 | 5 | 182 |
| Réglages · Général | standard | 473 | 388 | 382–395 | 5 | 175 |

### Volets et fenêtres

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Volet de menus | standard | 433 | 448 | 176–452 | 5 | 346 |
| Volet → accueil | standard | 205 | 275 | 267–284 | 5 | 750 |
| Volet · CPU | standard | 141 | 87 | 86–108 | 3 | — |
| Volet · GPU | standard | 67 | 83 | 63–84 | 3 | — |
| Volet · Mémoire | standard | 98 | 92 | 87–93 | 3 | — |
| Volet · Réseau | standard | 105 | 105 | 96–122 | 3 | — |
| Volet · Stockage | standard | 79 | 76 | 71–78 | 3 | — |
| Volet · Batterie | standard | 64 | 66 | 63–71 | 3 | — |
| Volet · Santé | standard | 61 | 83 | 75–90 | 3 | — |
| Volet latéral · ouverture manuelle | standard | 261 | 266 | 257–275 | 3 | — |
| Volet latéral · fermeture manuelle | standard | 254 | 271 | 268–271 | 3 | — |
| Volet → fenêtre fermée | données d’essai | — | 1213 | mesure unique | 1 | — |
| Volet CPU · 30 min | données d’essai | — | 332 | mesure unique | 1 | — |
| Volet CPU · 1 h | données d’essai | — | 159 | mesure unique | 1 | — |
| Volet CPU · 10 min | données d’essai | — | 152 | mesure unique | 1 | — |

### Premier lancement

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Bienvenue · automatisation | données d’essai | 34 | 30 | mesure unique | 1 | — |
| Bienvenue · accès disque | données d’essai | 34 | 36 | mesure unique | 1 | — |
| Bienvenue · assistant | données d’essai | 116 | 112 | mesure unique | 1 | — |
| Bienvenue · terminer | données d’essai | 459 | 347 | mesure unique | 1 | — |

### Clics physiques

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Souris · Batterie | données d’essai | — | 644 | mesure unique | 1 | — |
| Souris · Performances | données d’essai | — | 306 | mesure unique | 1 | — |
| Souris · Applications | données d’essai | — | 375 | mesure unique | 1 | — |
| Souris · Mes fichiers | données d’essai | — | 352 | mesure unique | 1 | — |
| Souris · Espace disque | données d’essai | — | 280 | mesure unique | 1 | — |
| Souris · Nettoyage | données d’essai | — | 315 | mesure unique | 1 | — |
| Souris · À propos | données d’essai | — | 279 | mesure unique | 1 | — |
| Souris · Accueil | données d’essai | — | 370 | mesure unique | 1 | — |
| Souris · carte Batterie | données d’essai | — | 665 | mesure unique | 1 | — |
| Souris · carte Outils | données d’essai | — | 289 | mesure unique | 1 | — |

### Règles de nettoyage

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Règles · Caches des apps sandboxées | données d’essai | — | 42 | mesure unique | 1 | — |
| Règles · Caches des apps Electron | données d’essai | — | 27 | mesure unique | 1 | — |
| Règles · Caches utilisateur | données d’essai | — | 27 | mesure unique | 1 | — |
| Règles · Caches partagés des apps | données d’essai | — | 26 | mesure unique | 1 | — |
| Règles · Téléchargements incomplets | données d’essai | — | 37 | mesure unique | 1 | — |
| Règles · Installateurs téléchargés | données d’essai | — | 33 | mesure unique | 1 | — |
| Règles · Sauvegardes d'appareils iOS | données d’essai | — | 34 | mesure unique | 1 | — |
| Règles · Logs utilisateur | données d’essai | — | 36 | mesure unique | 1 | — |
| Règles · Pièces jointes Mail ouvertes | données d’essai | — | 30 | mesure unique | 1 | — |
| Règles · Préférences illisibles | données d’essai | — | 31 | mesure unique | 1 | — |
| Règles · Archives Xcode | données d’essai | — | 33 | mesure unique | 1 | — |
| Règles · Journaux d'appareils Xcode | données d’essai | — | 33 | mesure unique | 1 | — |
| Règles · Supports d'appareils macOS | données d’essai | — | 36 | mesure unique | 1 | — |
| Règles · Supports d'appareils tvOS | données d’essai | — | 35 | mesure unique | 1 | — |
| Règles · Supports d'appareils visionOS | données d’essai | — | 44 | mesure unique | 1 | — |
| Règles · Supports d'appareils watchOS | données d’essai | — | 26 | mesure unique | 1 | — |
| Règles · Supports d'appareils Xcode | données d’essai | — | 27 | mesure unique | 1 | — |
| Règles · Cache de documentation Xcode | données d’essai | — | 29 | mesure unique | 1 | — |

### Données locales

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Confidentialité · Autres données locales | données d’essai | — | 46 | mesure unique | 1 | — |
| Confidentialité · Navigateurs | données d’essai | — | 23 | mesure unique | 1 | — |

### Détail des résultats

| Parcours | Session DEV | Réf. | DEV | Min–max DEV | n | Rendu DEV |
| --- | --- | --- | --- | --- | --- | --- |
| Bilan · Logs utilisateur | données d’essai | — | 50 | mesure unique | 1 | — |
| Bilan · Caches des apps Electron | données d’essai | — | 39 | mesure unique | 1 | — |
| Bilan · Caches utilisateur | données d’essai | — | 130 | mesure unique | 1 | — |

## Fenêtre 1 728 × 1 050 points

Reprise des rubriques, des gestionnaires et des clics souris dans une fenêtre agrandie sur le même Mac. Un passage par parcours.

| Parcours | Commandes en place (ms) |
| --- | --- |
| Accueil | 244 |
| Nettoyage | 181 |
| Performances | 168 |
| Batterie | 182 |
| Applications | 243 |
| Mes fichiers | 177 |
| Espace disque | 240 |
| À propos | 159 |
| Batterie · Protection de la batterie | 96 |
| Batterie · Profils d’utilisation | 101 |
| Batterie · Décharge contrôlée | 66 |
| Batterie · Programmations | 155 |
| Batterie · Historique | 100 |
| Batterie · Appareils Apple | 68 |
| Accès rapide | 261 |
| Outils · nettoyage d’écran | 396 |
| Mes outils | 196 |
| Outils · Santé des disques | 172 |
| Outils · Mode nettoyage d’écran | 179 |
| Outils · Fichiers IA inutiles | 212 |
| Outils · Autorisations des applications | 204 |
| Outils · Réparer l’affichage | 184 |
| Outils · Gérer le démarrage | 255 |
| Outils · Caches et données locales | 187 |
| Fichiers · Doublons | 193 |
| Fichiers · Gros fichiers | 223 |
| Fichiers · Images PNG | 197 |
| Souris · Batterie | 647 |
| Souris · Performances | 284 |
| Souris · Applications | 356 |
| Souris · Mes fichiers | 303 |
| Souris · Espace disque | 270 |
| Souris · Nettoyage | 309 |
| Souris · À propos | 286 |
| Souris · Accueil | 402 |
| Souris · carte Batterie | 675 |
| Souris · carte Outils | 301 |

## Correctifs et vérifications fonctionnelles

- **Volet de menus et fenêtre principale.** « Ouvrir MacCare » ramène la fenêtre principale devant les Réglages et restaure la fenêtre réduite. Les deux situations ont été rejouées trois fois chacune avec une seule fenêtre principale. Après fermeture complète, le volet en recrée une et l’accueil répond. Les cartes du volet apparaissent ensemble dans le fondu du panneau.
- **Barre latérale.** Un passage de 80 ms au-dessus des icônes laisse le volet replié. Sur trois essais, la détection de l’ouverture au survol a pris 300 à 388 ms et celle de la fermeture 385 à 432 ms. L’origine du bouton suivi reste identique et il retrouve ses dimensions au repli.
- **Nettoyage et Mes fichiers.** La navigation reste disponible pendant une lecture. Sur l’ancien écran Simulateurs, Retour et le sélecteur étaient tous deux désactivés pendant l’inventaire Xcode. Sur la candidate, les deux répondaient pendant ce même inventaire. Un clic sur Retour a effectivement ramené à Nettoyage. Le pied de page réserve son emplacement dès l’ouverture et les actions d’écriture conservent leurs protections.
- **Sélecteur Nettoyage.** Le bandeau du gestionnaire conserve sa vue native quand on change d’outil. Un clic à la souris ou l’activation macOS à 100, 250 et 450 ms après le changement ouvre bien le menu dans les six essais. Sur la candidate précédente le sélecteur était recréé à chacune des six transitions. Dans la build finale, son identité native est conservée six fois sur six. Le chronomètre de ce contrôle part de la fermeture effective du menu macOS, qui anime lui-même la sélection.
- **Réglages.** Les huit panneaux partagent une hauteur de contenu de 620 points avec défilement. L’ouverture et la réactivation actualisent les autorisations. Le changement d’onglet conserve la fenêtre et la position de ses commandes de navigation.
- **Batterie et outils.** Les cartes déclenchent leur navigation à la souris et par l’action d’activation native de macOS. La page Batterie garde un emplacement pour les premières mesures. Applications et Performances ne laissent plus activer les boutons du bilan recouvert par leur gestionnaire. Le même traitement est appliqué à Batterie.
- **Accueil et Applications.** L’accueil évite deux collectes de données dont il n’affichait plus le résultat. La sélection des icônes d’aperçu est déterministe. La recherche clavier de WindowServer retourne une seule ligne sur la machine d’essai et le clic ouvre sa fiche. Les commandes de la fiche ont gardé leur position sur deux relevés espacés de 550 ms.
- **Nettoyage par catégorie.** Les 18 règles disponibles ont été ouvertes et leur description vérifiée dans le panneau de détail. Les deux catégories de données locales et le retour aux résultats d’une analyse ont été contrôlés séparément.
- **Parcours rapides et cas conditionnels.** Après 36 navigations enchaînées, l’accueil est utilisable dans une seule fenêtre principale. Échap ramène du gestionnaire Nettoyage au bilan. Le premier lancement, les trois présentations du disque, un dossier enfant, les bilans et fiches conditionnelles ont été exercés avec un petit jeu de fichiers et une application fictive déclarée incompatible.
- **Cadre natif des Réglages.** Les huit onglets ont été sélectionnés successivement. La position et les dimensions extérieures étaient identiques à chaque étape.
- **Défilement des processus.** Une molette simulée sur le tableau a changé la première ligne visible. Le clic au centre d’une nouvelle ligne a ouvert sa fiche et le bouton de fermeture a répondu.
- **Sélecteur PNG et entretien.** Le clic physique sur le choix des images ouvre le sélecteur natif de macOS. Annuler revient au gestionnaire. La confirmation de réparation a aussi été ouverte puis annulée.

## Méthode et limites

- MacBook Pro 13 pouces M1 (MacBookPro17,1), 8 Go, macOS 27.0.1 (26A434). Les autres géométries ont été exercées sur cette même machine. Les passages à 1 436 × 800 et 1 728 × 1 050 utilisent l’aperçu compact DEV à 85 %. Une vérification sur des MacBook physiques 14 et 16 pouces reste ouverte.
- Le chronomètre démarre à l’activation du contrôle. Le parcours attend un repère de destination et des contrôles actifs. Leur rôle et leur rectangle, arrondi au point, doivent ensuite rester identiques pendant au moins 200 ms sur trois observations ou plus. La mesure publiée remonte au début de cet intervalle. Elle inclut le coût d’observation par l’accessibilité macOS. Les listes et les valeurs qui se mettent à jour en direct sont traitées à part. La fiche processus est contrôlée selon le protocole de 550 ms décrit plus haut.
- Le rendu des parcours principaux est aussi observé directement sur la fenêtre DEV via WindowServer. L’image est sous-échantillonnée tous les cinq pixels. Une différence de plus de 12 niveaux sur une composante couleur dans plus de 0,8 % des points marque une variation. 106 observations ont une fin stable d’au moins 200 ms. Les graphes, chiffres et inventaires peuvent continuer à évoluer. Ces mesures ne détectent pas chaque image perdue.
- Les parcours Performances · Éléments d’ouverture, Batterie · Appareils Apple, Volet → accueil ont chacun une capture qui changeait encore sur le dernier échantillon. Ces prises figurent dans le CSV et sont exclues des médianes de rendu. Tous ces parcours ont ensuite fourni une observation avec une fin stable confirmée.
- Sur Appareils Apple, les 68 relevés supplémentaires couvrent la lecture du matériel à deux densités. Le bouton Actualiser se déplace d’un point au maximum en mode compact. Les quatre autres commandes suivies sont restées fixes. À la densité normale, les cinq commandes ont gardé leur position.
- Les analyses, les inventaires et les écritures n’ont pas été chronométrés. Une commande de navigation qui attend leur fin se traduit néanmoins par une attente visible dans l’essai. Des lectures ont préparé les bilans et le dossier d’essai. Les essais d’interface s’arrêtent aux états et dialogues pour les actions ayant un effet sur les données, le matériel, les autorisations ou les mises à jour. Les boutons sensibles n’ont pas tous été déclenchés et le parcours VoiceOver complet reste à tester.
- Le bouton du diagnostic de compatibilité de la batterie n’était pas proposé sur cette machine dans l’état testé. Les alertes déclenchées par un événement matériel, les autorisations gérées par les Réglages Système de macOS et le parcours de mise à jour publique Sparkle ne font pas partie des pages chronométrées.
- Les scénarios de référence interrompus sont repérables dans le CSV. Les marqueurs d’ouverture des Réglages et de Nettoyage ont été corrigés puis les parcours rejoués. Sur la candidate, un relevé a rencontré une coordonnée transitoire non finie et une sélection a été envoyée avant la fermeture du précédent menu macOS. Les deux scénarios ont été rejoués avec succès après adaptation de la sonde. Les séries prises à des moments différents ne permettent pas d’attribuer toutes les différences à la version. La série alternée ci-dessus limite cet effet pour les rubriques communes.
- Tests de code et de packaging terminés avec 825 succès et 9 cas optionnels ignorés. XCTest compte 410 succès et 7 cas ignorés, Swift Testing 295 succès, Rust 99 succès et 2 cas ignorés, et le packaging 21 succès.

## Paquet préparé

Archive locale `MacCare-Dev-0.2.42-arm64.zip`, signée pour le développement Apple, identifiant de build 44. Le paquet extrait a été comparé au bundle testé, fichiers et liens symboliques compris. La vérification stricte de signature a réussi. Cette candidate n’a pas été distribuée sur GitHub ou Sparkle.

SHA-256 du ZIP : `4c39dbf0aa59222b6ff86852e4b62b0b996117583be1a0074b90e77b8293c41c`.

Le fichier `Mesures-interface-0.2.42.csv` accompagne l’archive. Chaque ligne indique la version, le parcours, les conditions, le moyen d’activation et les mesures disponibles.

## 24 novembre 2026 · Clic sur les cases du désinstalleur en DEV, build 45

La campagne de la build 44 contrôlait l’ouverture du gestionnaire Applications. Elle laissait de côté le clic au centre des cases de l’application et de ses données associées. À 85 %, les quatre clics au centre échouaient sur le jeu d’essai. Il fallait descendre de 32 points pour atteindre la première case. À 100 %, les quatre cases répondaient au centre.

Le gestionnaire appliquait la densité compacte à toute la vue scindée. Le séparateur AppKit travaillait en points de fenêtre, tandis que les cases étaient dessinées dans le repère réduit. Dans la build 45, le séparateur garde son repère natif et chaque colonne adapte son propre contenu. Le gestionnaire des applications inutilisées, incompatibles et des installateurs utilise la même disposition.

Le test de régression `UninstallPointerTests` affiche le désinstalleur dans une fenêtre macOS avec une application temporaire et trois fichiers associés. Il repère le centre de chaque coche dans l’image rendue et y envoie un appui et un relâchement de souris. Il vérifie l’identité du seul fichier coché, puis le décoche au même endroit. Il répète les contrôles après déplacement de la barre de défilement et vérifie que la position des coches a changé. Les essais couvrent les densités de 85 %, 90 % et 100 %. Rejoué sur le code précédent, le même test échoue à 85 % et 90 % et réussit à 100 %. Sur la candidate, la suite Swift compte 413 succès XCTest, sept cas ignorés et 295 succès Swift Testing. La session étant verrouillée, ces événements ont été envoyés à la fenêtre de test. Le jeu d’essai ne déclenche aucune désinstallation.

Candidate locale pour Mac Apple Silicon, `MacCare-Dev-0.2.42-45-arm64.zip`, signée pour le développement Apple. Les 254 entrées du paquet réextrait, dont neuf liens symboliques, correspondent au paquet d’origine. La signature stricte du paquet réextrait est valide. SHA-256 du ZIP `b638d4c58beb42eb83a95463c83c2d6aa82dae4d25da4067e17b1d820fc1c66d`.
