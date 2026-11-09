# Préparation de MacCare 0.2.20

9 novembre 2026. Publication demandée par Gregory avec le bilan Applications et
les changements de la discussion « Repenser l’onglet batterie ».

Base : `253abdc`, fusion de la PR #27 et CI après fusion réussie
[42649593010](https://github.com/M0okz/maccare/actions/runs/42649593010).
Le commit `a949a9e` du worktree `codex/update-availability` est repris sur la
branche `codex/release-0.2.20` sans modifier son checkout d’origine.

La refonte Batterie, la réparation de l’assistant et les priorités des
accessoires sont déjà publiées en 0.2.19 et conservées. L’ajout encore non livré
de la discussion est le rappel global de mise à jour ouvrant le changelog.
Les [notes utilisateur](release-notes/0.2.20.md) décrivent le périmètre final.

La publication suit la chaîne officielle GitHub : tests, signatures Developer
ID, notarisation, agrafage et signatures Sparkle, puis vérification des assets
publics. Le site sera actualisé après obtention du DMG final et de son empreinte.
Aucune installation ni remplacement des copies quotidiennes n’est demandé.
Les validations natives antérieures et leurs limites sont détaillées dans
[le bilan Applications](applications-insights.md) et [le rappel global](update-availability-notice.md).
