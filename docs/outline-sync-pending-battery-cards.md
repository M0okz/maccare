# Outline rétabli — Batterie par blocs

Synchronisation terminée le 9 novembre 2026 : huit pages relues et mises à jour
pour la livraison 0.2.19, contenu antérieur, collection et parents conservés.
Le blocage initial ci-dessous est historique.

9 novembre 2026, branche `codex/battery-cards`, base `ddc711d`.
Voir [la refonte et ses vérifications](battery-cards.md).

La maquette est validée ; l’implémentation est en développement, non livrée.
Le 9 novembre, les deux accès prescrits ont été essayés depuis le dépôt produit :
`homelab.py doctor --project …/maccare --service bitwarden`, puis
`homelab.py bw-exec --project …/maccare` pour rechercher l’entrée
« Outline - API documentaire » sans afficher ses valeurs. Tous deux ont échoué
avec le code 2 et le message suivant :

```text
Homelab environment failed (file, format, command or timeout); no values displayed
```

Aucun accès Outline confirmé, aucune écriture documentaire externe annoncée.
Ce résultat ne prouve pas un refus d’authentification de l’API Outline.

À reprendre : lire les pages MacCare Batterie/interface, Développement (08)
et Exploitation/journal (11), puis documenter les six cartes, le résumé réel,
la palette Batterie conservée, les gestionnaires clairs intégrés, les contrôles
et confirmations préservés, la référence de développement, le paquet Dev et
les tests/limites consignés dans `battery-cards.md`. Préserver les historiques
datés et les évolutions sans rapport. Relire les pages après écriture.
