# MacCare 0.2.26 — iStat Menus, 10 novembre 2026

En préparation sur `codex/istat-build-versions`, non livré à ce stade.

Le refus de 7.50.2 vers 7.50.3 vient des métadonnées Bjango : les deux archives
annoncent 7.50, avec les builds 2394 et 2395. MacCare reconnaît les deux couples
vérifiés et épingle l’empreinte de l’archive officielle malgré `no_check` dans la
fiche du catalogue. Les contrôles d’identité, de version, de signataire,
d’architecture, Gatekeeper et de chemins restent actifs. Aucun outil Homebrew
n’est nécessaire pour l’installation directe.

« Catalogue public Homebrew » désigne la détection de version ; le texte précise
que Homebrew n’a pas besoin d’être installé et que le téléchargement vient de
l’éditeur. Le parcours brew reste réservé à une copie réellement gérée par brew.

## Vérifications locales

Le nouveau test optionnel reproduit l’erreur exacte avant correction (3,089 s),
puis remplace une copie isolée officielle 7.50.2 (2394) par 7.50.3 (2395). Signature
Bjango `Y93TK974AT`, Gatekeeper et nouvel inventaire validés ; la même version
n’est pas reproposée. Aucun lancement d’iStat ou de ses helpers, aucun changement
de l’installation personnelle. Les tests refusent aussi un build ancien, inconnu
ou un autre bundle et vérifient l’URL/empreinte épinglées du catalogue.

376 XCTest passent avec le parcours iStat actif (6 parcours optionnels ignorés),
269 Swift Testing et 19 tests Python réussissent. Le build Release arm64 réussit. Le contrôle d’absence d’outils
de développement au runtime passe. La confirmation sur le second Mac reste à faire.

Ces correspondances sont des exceptions explicites vérifiées. Un futur patch
ayant la même version courte nécessite une nouvelle vérification, sans deviner
son numéro publié à partir de son build. Une archive republiée différente reste
refusée. [Détails et références](application-update-installation.md).

Suivi : Homelab #110. Les copies utilisateur et Dev installées sont conservées.
