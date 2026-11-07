/*
 * maccare_core — frontière C du moteur.
 *
 * En-tête écrit à la main. Il peut être régénéré
 * avec cbindgen ; voir bridge/cbindgen.toml. Doit rester synchronisé avec core/src/ffi.rs.
 *
 * Contrat mémoire : toute chaîne renvoyée par maccare_scan_rule doit être libérée une seule
 * fois via maccare_string_free. La chaîne de maccare_version est statique et ne se libère pas.
 */
#ifndef MACCARE_CORE_H
#define MACCARE_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version du moteur (chaîne statique, ne pas libérer). */
const char *maccare_version(void);

/*
 * Scanne selon une règle TOML. Renvoie une chaîne JSON allouée :
 *   {"items":[...],"warnings":[...]}  en cas de succès
 *   {"error":"..."}                   en cas d'échec
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_scan_rule(const char *rule_toml);

/*
 * Valide des éléments contre les gardes de sûreté, sans rien supprimer.
 * Entrée : {"scope_root":"...","items":[{"path":"...","identity":{"device":N,"inode":N}}]}
 * Sortie : {"decisions":[{"path":"...","allowed":true/false,"refusal":"<code|null>"}]}
 *          ou {"error":"..."}.
 * L'appelant ne met à la corbeille que les chemins "allowed":true.
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_plan_removal(const char *input_json);

/*
 * Supprime DIRECTEMENT (sans corbeille) les éléments, chacun re-validé par les gardes.
 * Irréversible ; réservé au mode explicite. Même entrée que maccare_plan_removal.
 * Sortie : {"results":[{"path","allowed","refusal","removed","error"}]} ou {"error":"..."}.
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_execute_removal(const char *input_json);

/*
 * Inspecte une liste explicite de chemins (pour le désinstalleur). Ne supprime rien.
 * Entrée : {"category":"...","paths":["...","..."]}
 * Sortie : {"items":[...]} (même forme que maccare_scan_rule) ou {"error":"..."}.
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_inspect_paths(const char *input_json);

/*
 * Renvoie les métadonnées d'une règle TOML sans scanner.
 * Sortie : {"id","title","description","category","risk":"safe|review","icon","root",
 *           "min_size_setting"} ou {"error":"..."}.
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_rule_info(const char *rule_toml);

/*
 * Mesure les enfants directs d'un dossier (module « Espace disque »). Ne supprime rien.
 * Entrée : {"path":"...","budget_secs":20}  (budget_secs 0/absent = défaut moteur).
 * Sortie : {"path":"...","children":[{"path","size_bytes","is_dir","measured"}],"warnings":[...]}
 *          ou {"error":"..."}.
 * La valeur renvoyée doit être libérée avec maccare_string_free.
 */
char *maccare_measure_dir(const char *input_json);

/*
 * Tâches longues : annulation et progression.
 *
 * Un jeton MaccareTask se passe aux variantes *_task ci-dessous. Pendant que l'appel bloquant
 * tourne (sur un thread de travail), un autre thread peut lire la progression et annuler :
 * l'appel rend alors la main en moins de 50 ms avec "cancelled": true et un résultat vide.
 * Libérer le jeton après le retour de l'appel ; NULL est accepté partout.
 */
typedef struct MaccareTask MaccareTask;

MaccareTask *maccare_task_new(void);
void maccare_task_cancel(const MaccareTask *task);
/* Entrées de dossier lues et octets comptés jusqu'ici ; pointeurs de sortie NULL ignorés. */
void maccare_task_progress(const MaccareTask *task, uint64_t *entries, uint64_t *bytes);
void maccare_task_free(MaccareTask *task);

/* Variantes annulables : même entrée et sortie que maccare_scan_rule / maccare_measure_dir,
 * plus "cancelled": bool. À libérer avec maccare_string_free. */
char *maccare_scan_rule_task(const char *rule_toml, const MaccareTask *task);
char *maccare_measure_dir_task(const char *input_json, const MaccareTask *task);

/*
 * Gros fichiers du dossier personnel (hors ~/Library, entrées cachées et contenu des paquets).
 * Entrée : {"root":"...?","min_bytes":N?,"limit":N?,"budget_secs":N?}  (absent/0 = défauts ;
 *          root doit rester sous HOME, hors ~/Library).
 * Sortie : {"root","files":[{"path","size_bytes","modified","identity"}],"warnings",
 *           "complete","cancelled"} ou {"error":"..."}. Ne supprime rien.
 */
char *maccare_find_large_files_task(const char *input_json, const MaccareTask *task);

/*
 * Valide des fichiers personnels choisis dans « Gros fichiers », sans rien supprimer.
 * Entrée : {"root":"...?","items":[{"path":"...","identity":{"device":N,"inode":N}}]}
 * Sortie : {"decisions":[{"path","allowed","refusal"}]} ou {"error":"..."}.
 * L'appelant ne doit que METTRE À LA CORBEILLE les chemins autorisés : aucune suppression
 * directe n'existe pour ces fichiers.
 */
char *maccare_plan_user_files(const char *input_json);

/*
 * Doublons du dossier personnel (même périmètre que les gros fichiers, projets de code exclus).
 * Entrée : {"root":"...?","min_bytes":N?,"budget_secs":N?}
 * Sortie : {"root","groups":[{"length","reclaimable","files":[{"path","size_bytes","modified",
 *           "identity"}]}],"warnings","complete","cancelled"} ou {"error":"..."}. Ne supprime rien.
 */
char *maccare_find_duplicates_task(const char *input_json, const MaccareTask *task);

/*
 * Valide le retrait de doublons, sans rien supprimer. Par groupe, "keep" doit être présent et
 * inchangé et n'être retiré nulle part ; chaque fichier retiré doit avoir exactement son contenu.
 * Entrée : {"root":"...?","groups":[{"keep":{"path","identity"},"remove":[{"path","identity"}]}]}
 * Sortie : {"decisions":[{"path","allowed","refusal"}]} ou {"error":"..."}.
 * L'appelant ne doit que METTRE À LA CORBEILLE les chemins autorisés.
 */
char *maccare_plan_duplicates(const char *input_json);

/*
 * Corbeilles de l'utilisateur (~/.Trash, .Trashes/<uid> des volumes montés). Ne supprime rien.
 * Entrée ignorée ("{}"). Sortie : {"bins":[{"path","label","identity","items","size_bytes",
 * "measured","readable","snapshot"}],"cancelled"} ou {"error":"..."}.
 */
char *maccare_list_trashes_task(const char *input_json, const MaccareTask *task);

/*
 * Vide DÉFINITIVEMENT des corbeilles. Seules celles que le moteur repère lui-même sont admises ;
 * enfants directs uniquement, sans suivre de lien ni changer de volume, verrous jamais forcés.
 * Le contenu doit correspondre à "snapshot" (rendu par la liste), sinon refus "content-changed"
 * sans rien supprimer.
 * Entrée : {"bins":[{"path":"...","identity":{"device":N,"inode":N},"snapshot":"..."}]}
 * Sortie : {"results":[{"path","refusal","removed","freed_bytes","failures":[{"path","error"}]}],
 *           "cancelled"} ou {"error":"..."}.
 */
char *maccare_empty_trashes_task(const char *input_json, const MaccareTask *task);

/*
 * Simulateurs et runtimes Xcode, via xcrun simctl. Ne supprime rien. Entrée ignorée ("{}").
 * Sortie : {"xcode","simulators":[{"udid","name","runtime","runtime_identifier","state",
 *           "available","last_used","size_bytes"}],"runtimes":[{"identifier","name",
 *           "runtime_identifier","size_bytes","deletable","last_used","devices"}],"warnings","cancelled"}
 */
char *maccare_list_simulators_task(const char *input_json, const MaccareTask *task);

/*
 * Supprime DÉFINITIVEMENT simulateurs et runtimes via xcrun simctl. Liste fermée relue par le
 * moteur ; simulateur allumé ou runtime non supprimable refusé.
 * Entrée : {"simulators":["<udid>"],"runtimes":["<uuid>"]}
 * Sortie : {"results":[{"id","removed","error"}],"cancelled"} ou {"error":"..."}.
 */
char *maccare_delete_simulators_task(const char *input_json, const MaccareTask *task);

/*
 * Agents de lancement : utilisateur, mis de côté par MacCare, système (lecture seule).
 * Entrée ignorée ("{}"). Sortie : {"agents":[{"path","label","scope","program","orphan","loaded",
 * "running","managed_by","apple","identity","original_path"}]}. Ne modifie rien.
 */
char *maccare_list_agents_task(const char *input_json, const MaccareTask *task);

/*
 * Désactive / réactive un agent de l'utilisateur (réversible, atomique). Liste fermée relue par le
 * moteur ; jamais un agent système ni Apple.
 * Entrée : {"action":"disable|enable","path":"...","identity":{"device":N,"inode":N}}
 * Sortie : {"ok":true,"path":"..."} ou {"ok":false,"error":"..."}.
 */
char *maccare_set_agent_task(const char *input_json, const MaccareTask *task);

/*
 * Règles système fermées (assistant privilégié). La règle est un identifiant compilé dans le
 * moteur ("sys.logs.library", "sys.logs.diagnostic-reports", "sys.logs.rotated") ; jamais un chemin.
 * maccare_system_list   : {"rule":"..."} -> {"items":[...],"skipped":[...],"truncated"} ; ne modifie rien.
 * maccare_system_remove : {"rule":"...","identities":[{"device","inode"}]} -> {"removed","freed_bytes",
 *                         "refused","not_found","truncated"} ; suppression DÉFINITIVE, règle réénumérée.
 */
char *maccare_system_list(const char *input_json);
char *maccare_system_remove(const char *input_json);

/* Crée une copie PNG allégée, sans écraser aucun fichier existant. */
char *maccare_optimize_png_copy(const char *input_json);

/* Libère une chaîne renvoyée par les fonctions ci-dessus. NULL accepté. */
void maccare_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* MACCARE_CORE_H */
