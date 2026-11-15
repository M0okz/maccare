# MacCare 0.2.29 — protection M1 Max

En préparation le 15 novembre 2026, à la demande explicite de Gregory de recevoir
le correctif par la mise à jour publique de MacCare. Base : 0.2.28, corrections
de stabilité conservées. Aucune installation utilisateur effectuée par ce chantier.

## Contenu

- Distinction entre priorité Apple de recharge complète et état illisible ;
  disparition du diagnostic infondé d'étalonnage en cours.
- Méthode avancée disponible en validation pour le seul `MacBookPro18,4`, avec
  CHIE et les garde-fous de journal/restauration, de température et de priorité Apple.
- Statut expérimental visible dans la protection et sa confirmation ; aucun
  ajout à la liste des modèles matériellement validés.
- Diagnostic CLI complet en lecture seule, 40 tentatives SMC dont quatre CHIE,
  télémétrie et compatibilité ; arguments inconnus refusés sans démarrer le service.
- Variante autonome de diagnostic conservée, sans démarrage de daemon.

La release fixe explicitement `MACCARE_M1_MAX_BATTERY_TRIAL=1` et
`MACCARE_PUBLIC_M1_MAX_TRIAL=1`. Le packaging vérifie le mode compilé du helper
et exige ce choix explicite pour la distribution. Le manifeste et Info.plist
consignent l'inclusion du mode M1 Max. Le nom distribué reste **MacCare**, avec
le flux Sparkle signé habituel ; ce n'est plus seulement une archive MacCare Dev.

## Limites

La lecture root distante de CHIE, la limite native et l'interface avancée ont été
observées sur MacBookPro18,4/macOS 27.2. Les essais matériels de maintien, reprise,
veille et restauration restent à réaliser. Une priorité Apple active ou illisible
continue de bloquer les écritures ; la nouvelle version ne garantit pas une
activation immédiate tant que ce signal persiste.

Les contrôles de livraison et leurs références seront consignés après publication.
L'accès Outline prévu a été essayé et échoue avec `Bitwarden status failed` ;
les pages batterie, développement, publication et dépannage restent à synchroniser.
