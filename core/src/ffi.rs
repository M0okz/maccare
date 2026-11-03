//! Frontière C stable pour les consommateurs non-Rust (Swift).
//!
//! Les données structurées transitent en **JSON** (voir la spec §4) afin d'éviter une ABI
//! fragile ; seule la gestion mémoire des chaînes traverse la frontière en C brut.
//!
//! Robustesse : chaque point d'entrée s'exécute sous [`guarded`] — une panique Rust ne traverse
//! jamais la frontière (ce serait un abandon du processus hôte) ; elle devient `{"error":...}`.
//!
//! Contrat mémoire : toute chaîne renvoyée par cette couche doit être libérée **une seule fois**
//! via [`maccare_string_free`]. L'exception est [`maccare_version`], dont la chaîne est statique
//! et ne doit pas être libérée.

use crate::clean::{self, RemovalMode};
use crate::model::{FileIdentity, ScanItem};
use crate::rules::Rule;
use crate::safety::{self, Decision, Refusal, SafetyContext};
use crate::scan::{inspect_paths, measure_children_with, scan_rule_with, MEASURE_DEFAULT_BUDGET, RULE_SCAN_BUDGET};
use crate::walk::{Budget, Control};
use std::sync::Arc;
use serde::Deserialize;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::time::Duration;

/// Version du moteur, chaîne statique terminée par NUL. Ne pas libérer.
#[no_mangle]
pub extern "C" fn maccare_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

// ---------------------------------------------------------------------------
// Tâches longues : annulation et progression.
// ---------------------------------------------------------------------------

/// Jeton opaque d'une tâche longue (scan, mesure). Permet de l'annuler et d'en lire la
/// progression **depuis un autre thread** pendant que l'appel bloquant est en cours.
pub struct MaccareTask(Arc<Control>);

impl MaccareTask {
    /// Contrôle du jeton, ou un contrôle neuf si le pointeur est nul.
    unsafe fn control(task: *const MaccareTask) -> Arc<Control> {
        task.as_ref().map(|t| Arc::clone(&t.0)).unwrap_or_else(Control::new)
    }
}

/// Crée un jeton de tâche. À libérer avec [`maccare_task_free`].
#[no_mangle]
pub extern "C" fn maccare_task_new() -> *mut MaccareTask {
    Box::into_raw(Box::new(MaccareTask(Control::new())))
}

/// Demande l'annulation : l'appel en cours rend la main en moins de 50 ms avec
/// `"cancelled": true`. Sans effet sur un pointeur nul. Appelable depuis n'importe quel thread.
///
/// # Safety
/// `task` doit être nul ou provenir de [`maccare_task_new`] et ne pas avoir été libéré.
#[no_mangle]
pub unsafe extern "C" fn maccare_task_cancel(task: *const MaccareTask) {
    if let Some(t) = task.as_ref() {
        t.0.cancel();
    }
}

/// Lit la progression : entrées de dossier lues et octets comptés jusqu'ici. Les pointeurs de
/// sortie nuls sont ignorés. Appelable depuis n'importe quel thread pendant la tâche.
///
/// # Safety
/// `task` doit être nul ou un jeton valide ; `entries`/`bytes` nuls ou inscriptibles.
#[no_mangle]
pub unsafe extern "C" fn maccare_task_progress(task: *const MaccareTask, entries: *mut u64, bytes: *mut u64) {
    let Some(t) = task.as_ref() else { return };
    if let Some(e) = entries.as_mut() {
        *e = t.0.entries();
    }
    if let Some(b) = bytes.as_mut() {
        *b = t.0.bytes();
    }
}

/// Libère un jeton. Nul est accepté et ignoré. Les workers encore détachés gardent leur propre
/// référence : libérer après le retour de l'appel est toujours sûr.
///
/// # Safety
/// `task` doit provenir de [`maccare_task_new`], n'être libéré qu'une fois, et plus aucun appel
/// ne doit l'utiliser ensuite.
#[no_mangle]
pub unsafe extern "C" fn maccare_task_free(task: *mut MaccareTask) {
    if !task.is_null() {
        drop(Box::from_raw(task));
    }
}

/// Scanne selon une règle fournie au format TOML. Renvoie une chaîne JSON allouée :
/// `{"items":[...],"warnings":[...]}` en cas de succès, `{"error":"..."}` sinon.
///
/// # Safety
/// `rule_toml` doit être soit nul, soit un pointeur valide vers une chaîne C terminée par NUL.
/// La valeur renvoyée doit être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_scan_rule(rule_toml: *const c_char) -> *mut c_char {
    guarded(|| scan_to_json(rule_toml, Control::new()))
}

/// Comme [`maccare_scan_rule`], sous un jeton de tâche (annulable, progression observable).
/// Sortie : celle de [`maccare_scan_rule`] plus `"cancelled": bool` (éléments vides si vrai).
///
/// # Safety
/// `rule_toml` : comme [`maccare_scan_rule`]. `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_scan_rule_task(rule_toml: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| scan_to_json(rule_toml, control))
}

unsafe fn scan_to_json(rule_toml: *const c_char, control: Arc<Control>) -> String {
    if rule_toml.is_null() {
        return error_json("pointeur de règle nul");
    }
    let toml_src = match CStr::from_ptr(rule_toml).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("règle non-UTF-8"),
    };
    let rule = match Rule::from_toml(toml_src) {
        Ok(r) => r,
        Err(e) => return error_json(&e.to_string()),
    };
    let outcome = scan_rule_with(&rule, Budget::new(RULE_SCAN_BUDGET), &control);
    serde_json::json!({
        "items": outcome.items,
        "warnings": outcome.warnings,
        "cancelled": outcome.cancelled,
    })
    .to_string()
}

/// Entrée de [`maccare_inspect_paths`].
#[derive(Deserialize)]
struct InspectInput {
    category: String,
    paths: Vec<String>,
}

/// Inspecte une liste explicite de chemins et renvoie un `ScanItem` pour chacun qui existe
/// (hors liens symboliques). Destiné au désinstalleur. Ne supprime rien.
///
/// Entrée JSON : `{"category":"...","paths":["...","..."]}`.
/// Sortie JSON : `{"items":[...]}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL. La valeur renvoyée doit
/// être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_inspect_paths(input_json: *const c_char) -> *mut c_char {
    guarded(|| inspect_to_json(input_json))
}

unsafe fn inspect_to_json(input_json: *const c_char) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: InspectInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };

    // Mesure groupée : tous les chemins partagent le même pool de workers.
    let paths: Vec<std::path::PathBuf> = input.paths.iter().map(std::path::PathBuf::from).collect();
    let items: Vec<ScanItem> = inspect_paths(&paths, &input.category, "uninstall");

    serde_json::json!({ "items": items }).to_string()
}

/// Renvoie les métadonnées d'une règle TOML (titre, risque, racine développée…) sans scanner.
///
/// Sortie JSON : `{"id","title","description","category","risk","icon","root","min_size_setting","audience"}`
/// ou `{"error":"..."}`.
///
/// # Safety
/// `rule_toml` doit être nul ou une chaîne C valide terminée par NUL. La valeur renvoyée doit
/// être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_rule_info(rule_toml: *const c_char) -> *mut c_char {
    guarded(|| rule_info_to_json(rule_toml))
}

unsafe fn rule_info_to_json(rule_toml: *const c_char) -> String {
    if rule_toml.is_null() {
        return error_json("pointeur de règle nul");
    }
    let src = match CStr::from_ptr(rule_toml).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("règle non-UTF-8"),
    };
    let rule = match Rule::from_toml(src) {
        Ok(r) => r,
        Err(e) => return error_json(&e.to_string()),
    };
    serde_json::json!({
        "id": rule.id,
        "title": if rule.title.is_empty() { rule.id.clone() } else { rule.title.clone() },
        "description": rule.description,
        "category": rule.category,
        "risk": rule.risk,
        "icon": rule.icon,
        "root": rule.root_path().to_string_lossy(),
        "min_size_setting": rule.min_size_setting,
        "audience": rule.audience,
    })
    .to_string()
}

/// Entrée de [`maccare_measure_dir`].
#[derive(Deserialize)]
struct MeasureInput {
    path: String,
    /// Budget global de mesure, en secondes (0 ou absent = valeur par défaut du moteur).
    #[serde(default)]
    budget_secs: u64,
}

/// Mesure les enfants directs d'un dossier (module « Espace disque »). Ne supprime rien.
///
/// Entrée JSON : `{"path":"...","budget_secs":20}`.
/// Sortie JSON : `{"path":"...","children":[{"path","size_bytes","is_dir","measured"}],"warnings":[...]}`
/// ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL. La valeur renvoyée doit
/// être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_measure_dir(input_json: *const c_char) -> *mut c_char {
    guarded(|| measure_to_json(input_json, Control::new()))
}

/// Comme [`maccare_measure_dir`], sous un jeton de tâche (annulable, progression observable).
/// Sortie : celle de [`maccare_measure_dir`] plus `"cancelled": bool` (enfants vides si vrai).
///
/// # Safety
/// `input_json` : comme [`maccare_measure_dir`]. `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_measure_dir_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| measure_to_json(input_json, control))
}

unsafe fn measure_to_json(input_json: *const c_char, control: Arc<Control>) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: MeasureInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };

    let budget = if input.budget_secs == 0 {
        MEASURE_DEFAULT_BUDGET
    } else {
        Duration::from_secs(input.budget_secs)
    };
    let outcome = measure_children_with(Path::new(&input.path), budget, &control);
    let children: Vec<serde_json::Value> = outcome
        .children
        .iter()
        .map(|c| {
            serde_json::json!({
                "path": c.path,
                "size_bytes": c.size_bytes,
                "is_dir": c.is_dir,
                "measured": c.measured,
            })
        })
        .collect();

    serde_json::json!({
        "path": input.path,
        "children": children,
        "warnings": outcome.warnings,
        "cancelled": outcome.cancelled,
    })
    .to_string()
}

/// Entrée d'une demande de plan de retrait.
#[derive(Deserialize)]
struct PlanInput {
    /// Racine de la règle qui a produit les éléments (confinement). Ignorée si `rule` est fourni :
    /// la racine de la règle fait alors foi.
    #[serde(default)]
    scope_root: String,
    /// Texte TOML de la règle qui a proposé les éléments. Si présent, chaque élément est re-validé
    /// contre elle ([`safety::evaluate_for_rule`]) ; une règle invalide fait échouer tout l'appel.
    #[serde(default)]
    rule: Option<String>,
    items: Vec<PlanItem>,
}

/// Fonction de décision retenue pour une demande de retrait.
enum Validator {
    Scope(std::path::PathBuf),
    Rule(Box<Rule>),
}

impl Validator {
    fn from_input(input: &PlanInput) -> Result<Self, String> {
        match &input.rule {
            Some(src) => Rule::from_toml(src).map(|r| Validator::Rule(Box::new(r))).map_err(|e| e.to_string()),
            None if input.scope_root.trim().is_empty() => Err("scope_root ou rule requis".into()),
            None => Ok(Validator::Scope(std::path::PathBuf::from(&input.scope_root))),
        }
    }

    fn evaluate(&self, ctx: &SafetyContext, path: &Path, identity: FileIdentity) -> Decision {
        match self {
            Validator::Scope(scope) => safety::evaluate(ctx, path, scope, identity),
            Validator::Rule(rule) => safety::evaluate_for_rule(ctx, path, rule, identity),
        }
    }
}

#[derive(Deserialize)]
struct PlanItem {
    path: String,
    identity: FileIdentity,
}

/// Valide une liste d'éléments contre les gardes de sûreté, **sans rien supprimer**.
///
/// L'appelant (Swift) ne doit mettre à la corbeille que les chemins marqués `allowed: true`.
/// La protection utilise l'ensemble par défaut dérivé de l'environnement.
///
/// Entrée JSON : `{"scope_root":"...","rule":"<toml>?","items":[{"path":"...","identity":{"device":N,"inode":N}}]}`.
/// Avec `rule`, chaque élément doit encore satisfaire la règle (enfant direct de sa racine,
/// inclusions, exclusions de nom) ; c'est la seule voie vers un arbre protégé, pour les règles à
/// liste blanche `include`. Règle illisible ou invalide : `{"error":...}`, rien n'est autorisé.
/// Sortie JSON : `{"decisions":[{"path":"...","allowed":bool,"refusal":"<code|null>"}]}`,
/// ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL. La valeur renvoyée doit
/// être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_plan_removal(input_json: *const c_char) -> *mut c_char {
    guarded(|| plan_to_json(input_json))
}

unsafe fn plan_to_json(input_json: *const c_char) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: PlanInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };

    let validator = match Validator::from_input(&input) {
        Ok(v) => v,
        Err(e) => return error_json(&e),
    };
    let ctx = SafetyContext::default_for_env();

    let decisions: Vec<serde_json::Value> = input
        .items
        .iter()
        .map(|item| {
            let decision = validator.evaluate(&ctx, Path::new(&item.path), item.identity);
            serde_json::json!({
                "path": item.path,
                "allowed": decision.is_allowed(),
                "refusal": refusal_code(&decision),
            })
        })
        .collect();

    serde_json::json!({ "decisions": decisions }).to_string()
}

/// Supprime **directement** (sans corbeille) les éléments d'une sélection, chacun re-validé
/// par les gardes de sûreté avant retrait. Opération irréversible, réservée au mode explicite.
///
/// Entrée JSON identique à [`maccare_plan_removal`].
/// Sortie JSON : `{"results":[{"path","allowed","refusal","removed","error"}]}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL. La valeur renvoyée doit
/// être libérée avec [`maccare_string_free`].
#[no_mangle]
pub unsafe extern "C" fn maccare_execute_removal(input_json: *const c_char) -> *mut c_char {
    guarded(|| execute_to_json(input_json))
}

unsafe fn execute_to_json(input_json: *const c_char) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: PlanInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };

    let validator = match Validator::from_input(&input) {
        Ok(v) => v,
        Err(e) => return error_json(&e),
    };
    let ctx = SafetyContext::default_for_env();

    // Reconstruit des ScanItem minimaux (seuls path et identity comptent pour le nettoyage).
    let items: Vec<ScanItem> = input
        .items
        .iter()
        .map(|it| {
            ScanItem::new(
                std::path::PathBuf::from(&it.path),
                "", // catégorie non pertinente ici
                "", // raison non pertinente ici
                0,
                false,
                it.identity,
            )
        })
        .collect();

    let results = match &validator {
        Validator::Scope(scope) => clean::execute(&ctx, scope, &items, RemovalMode::DirectDelete),
        Validator::Rule(rule) => clean::execute_for_rule(&ctx, rule, &items, RemovalMode::DirectDelete),
    };
    let json: Vec<serde_json::Value> = results
        .iter()
        .map(|r| {
            serde_json::json!({
                "path": r.path,
                "allowed": r.decision.is_allowed(),
                "refusal": refusal_code(&r.decision),
                "removed": r.removed,
                "error": r.error,
            })
        })
        .collect();

    serde_json::json!({ "results": json }).to_string()
}

// ---------------------------------------------------------------------------
// Gros fichiers (module « Gros fichiers »).
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct LargeInput {
    /// Racine de recherche ; défaut : le dossier personnel. Doit rester sous `HOME`, hors `~/Library`.
    #[serde(default)]
    root: Option<String>,
    #[serde(default)]
    min_bytes: u64,
    #[serde(default)]
    limit: usize,
    #[serde(default)]
    budget_secs: u64,
}

fn large_root(root: &Option<String>) -> Result<std::path::PathBuf, String> {
    let raw = match root {
        Some(r) => std::path::PathBuf::from(r),
        None => std::path::PathBuf::from(std::env::var("HOME").map_err(|_| "HOME indéfini")?),
    };
    crate::large::validate_root(&raw)
}

/// Recherche les plus gros fichiers du dossier personnel (hors `~/Library`, entrées cachées et
/// contenu des paquets), sous un jeton de tâche. Ne supprime rien.
///
/// Entrée JSON : `{"root":"...?","min_bytes":N?,"limit":N?,"budget_secs":N?}` (0/absent = défauts).
/// Sortie JSON : `{"root","files":[{"path","size_bytes","modified","identity"}],"warnings",
/// "complete","cancelled"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_find_large_files_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| large_to_json(input_json, control))
}

unsafe fn large_to_json(input_json: *const c_char, control: Arc<Control>) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: LargeInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };
    let root = match large_root(&input.root) {
        Ok(r) => r,
        Err(e) => return error_json(&e),
    };
    let min = if input.min_bytes == 0 { crate::large::DEFAULT_MIN_BYTES } else { input.min_bytes };
    let limit = if input.limit == 0 { crate::large::DEFAULT_LIMIT } else { input.limit };
    let budget = if input.budget_secs == 0 {
        crate::large::DEFAULT_BUDGET
    } else {
        Duration::from_secs(input.budget_secs)
    };
    let outcome = crate::large::find_large_files(&root, min, limit, Budget::new(budget), &control);
    serde_json::json!({
        "root": root,
        "files": outcome.files,
        "warnings": outcome.warnings,
        "complete": outcome.complete,
        "cancelled": outcome.cancelled,
    })
    .to_string()
}

#[derive(Deserialize)]
struct UserFilesInput {
    #[serde(default)]
    root: Option<String>,
    items: Vec<PlanItem>,
}

/// Valide des fichiers choisis dans le module « Gros fichiers », **sans rien supprimer**.
/// L'appelant ne doit que **mettre à la corbeille** les chemins autorisés : il n'existe pas de
/// suppression directe pour ces fichiers.
///
/// Entrée JSON : `{"root":"...?","items":[{"path":"...","identity":{"device":N,"inode":N}}]}`.
/// Sortie JSON : `{"decisions":[{"path","allowed","refusal"}]}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL.
#[no_mangle]
pub unsafe extern "C" fn maccare_plan_user_files(input_json: *const c_char) -> *mut c_char {
    guarded(|| user_files_to_json(input_json))
}

unsafe fn user_files_to_json(input_json: *const c_char) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: UserFilesInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };
    let root = match large_root(&input.root) {
        Ok(r) => r,
        Err(e) => return error_json(&e),
    };
    let ctx = SafetyContext::default_for_env();
    let decisions: Vec<serde_json::Value> = input
        .items
        .iter()
        .map(|item| {
            let decision = crate::large::evaluate(&ctx, Path::new(&item.path), &root, item.identity);
            serde_json::json!({
                "path": item.path,
                "allowed": decision.is_allowed(),
                "refusal": refusal_code(&decision),
            })
        })
        .collect();
    serde_json::json!({ "decisions": decisions }).to_string()
}

// ---------------------------------------------------------------------------
// Doublons (module « Doublons »).
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct DupesInput {
    #[serde(default)]
    root: Option<String>,
    #[serde(default)]
    min_bytes: u64,
    #[serde(default)]
    budget_secs: u64,
}

/// Recherche les doublons du dossier personnel (même périmètre que les gros fichiers), sous un
/// jeton de tâche. Ne supprime rien.
///
/// Entrée JSON : `{"root":"...?","min_bytes":N?,"budget_secs":N?}` (0/absent = défauts).
/// Sortie JSON : `{"root","groups":[{"length","reclaimable","files":[{"path","size_bytes",
/// "modified","identity"}]}],"warnings","complete","cancelled"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_find_duplicates_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| dupes_to_json(input_json, control))
}

unsafe fn dupes_to_json(input_json: *const c_char, control: Arc<Control>) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: DupesInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };
    let root = match large_root(&input.root) {
        Ok(r) => r,
        Err(e) => return error_json(&e),
    };
    let min = if input.min_bytes == 0 { crate::dupes::DEFAULT_MIN_BYTES } else { input.min_bytes };
    let budget = if input.budget_secs == 0 {
        crate::dupes::DEFAULT_BUDGET
    } else {
        Duration::from_secs(input.budget_secs)
    };
    let outcome = crate::dupes::find_duplicates(&root, min, Budget::new(budget), &control);
    let groups: Vec<serde_json::Value> = outcome
        .groups
        .iter()
        .map(|g| serde_json::json!({ "length": g.length, "reclaimable": g.reclaimable(), "files": g.files }))
        .collect();
    serde_json::json!({
        "root": root,
        "groups": groups,
        "warnings": outcome.warnings,
        "complete": outcome.complete,
        "cancelled": outcome.cancelled,
    })
    .to_string()
}

#[derive(Deserialize)]
struct DupesPlanGroup {
    keep: PlanItem,
    remove: Vec<PlanItem>,
}

#[derive(Deserialize)]
struct DupesPlanInput {
    #[serde(default)]
    root: Option<String>,
    groups: Vec<DupesPlanGroup>,
}

/// Valide le retrait de doublons, **sans rien supprimer**. Pour chaque groupe, `keep` est
/// l'exemplaire conservé : il doit être présent et inchangé, n'être retiré dans aucun groupe, et
/// chaque fichier retiré doit avoir **exactement** son contenu (comparaison octet par octet).
/// L'appelant ne doit que **mettre à la corbeille** les chemins autorisés.
///
/// Entrée JSON : `{"root":"...?","groups":[{"keep":{"path","identity"},"remove":[{"path","identity"}]}]}`.
/// Sortie JSON : `{"decisions":[{"path","allowed","refusal"}]}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL.
#[no_mangle]
pub unsafe extern "C" fn maccare_plan_duplicates(input_json: *const c_char) -> *mut c_char {
    guarded(|| plan_dupes_to_json(input_json))
}

unsafe fn plan_dupes_to_json(input_json: *const c_char) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: DupesPlanInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };
    let root = match large_root(&input.root) {
        Ok(r) => r,
        Err(e) => return error_json(&e),
    };
    let candidate = |i: &PlanItem| crate::dupes::Candidate {
        path: std::path::PathBuf::from(&i.path),
        identity: i.identity,
    };
    let groups: Vec<crate::dupes::PlanGroup> = input
        .groups
        .iter()
        .map(|g| crate::dupes::PlanGroup { keep: candidate(&g.keep), remove: g.remove.iter().map(candidate).collect() })
        .collect();
    let ctx = SafetyContext::default_for_env();
    let decisions: Vec<serde_json::Value> = crate::dupes::evaluate_groups(&ctx, &root, &groups)
        .iter()
        .map(|(path, d)| serde_json::json!({ "path": path, "allowed": d.is_allowed(), "refusal": refusal_code(d) }))
        .collect();
    serde_json::json!({ "decisions": decisions }).to_string()
}

// ---------------------------------------------------------------------------
// Corbeilles (module « Corbeilles ») — seule suppression définitive.
// ---------------------------------------------------------------------------

/// Repère et mesure les corbeilles de l'utilisateur (`~/.Trash`, `.Trashes/<uid>` des volumes).
/// Ne supprime rien. L'entrée est ignorée (passer `{}`).
///
/// Sortie JSON : `{"bins":[{"path","label","identity","items","size_bytes","measured","readable",
/// "snapshot"}],
/// "cancelled"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_list_trashes_task(_input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| {
        let bins = crate::trash::measure(&crate::trash::locate(), Budget::new(crate::trash::MEASURE_BUDGET), &control);
        serde_json::json!({ "bins": bins, "cancelled": control.is_cancelled() }).to_string()
    })
}

#[derive(Deserialize)]
struct EmptyBin {
    path: String,
    identity: FileIdentity,
    /// Empreinte rendue par `maccare_list_trashes_task` ; obligatoire.
    snapshot: String,
}

#[derive(Deserialize)]
struct EmptyInput {
    bins: Vec<EmptyBin>,
}

/// Vide **définitivement** les corbeilles demandées. Chacune doit figurer dans la liste fermée
/// que le moteur repère lui-même, être un vrai dossier de l'utilisateur et avoir l'identité
/// donnée ; seuls ses enfants directs sont retirés, sans suivre de lien ni changer de volume.
///
/// Le contenu doit être exactement celui de l'affichage (`snapshot`), sinon la corbeille est
/// refusée (`content-changed`) sans rien supprimer ; seuls les éléments vérifiés sont retirés.
///
/// Entrée JSON : `{"bins":[{"path":"...","identity":{"device":N,"inode":N},"snapshot":"..."}]}`.
/// Sortie JSON : `{"results":[{"path","refusal","removed","freed_bytes","failures":[{"path","error"}]}],
/// "cancelled"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_empty_trashes_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| empty_to_json(input_json, control))
}

unsafe fn empty_to_json(input_json: *const c_char, control: Arc<Control>) -> String {
    if input_json.is_null() {
        return error_json("pointeur d'entrée nul");
    }
    let src = match CStr::from_ptr(input_json).to_str() {
        Ok(s) => s,
        Err(_) => return error_json("entrée non-UTF-8"),
    };
    let input: EmptyInput = match serde_json::from_str(src) {
        Ok(v) => v,
        Err(e) => return error_json(&format!("entrée illisible : {e}")),
    };
    let requested: Vec<crate::trash::EmptyRequest> = input
        .bins
        .iter()
        .map(|b| crate::trash::EmptyRequest {
            path: std::path::PathBuf::from(&b.path),
            identity: b.identity,
            snapshot: b.snapshot.clone(),
        })
        .collect();
    let results: Vec<serde_json::Value> = crate::trash::empty(&requested, &control)
        .iter()
        .map(|r| {
            serde_json::json!({
                "path": r.path,
                "refusal": r.refusal,
                "removed": r.removed,
                "freed_bytes": r.freed_bytes,
                "failures": r.failures.iter().map(|(p, e)| serde_json::json!({ "path": p, "error": e })).collect::<Vec<_>>(),
            })
        })
        .collect();
    serde_json::json!({ "results": results, "cancelled": control.is_cancelled() }).to_string()
}

// ---------------------------------------------------------------------------
// Simulateurs Xcode (module « Simulateurs », outils pour développeurs).
// ---------------------------------------------------------------------------

/// Liste les simulateurs (taille de leurs données) et les runtimes via `simctl` (localisé par
/// `xcode-select -p`, jamais via `xcrun` : aucune fenêtre d'installation sur un Mac sans Xcode).
/// Ne supprime rien. L'entrée est ignorée (passer `{}`).
///
/// Sortie JSON : `{"xcode":bool,"simulators":[{"udid","name","runtime","runtime_identifier",
/// "state","available","last_used","size_bytes"}],"runtimes":[{"identifier","name",
/// "runtime_identifier","size_bytes","deletable","last_used","devices"}],"warnings","cancelled"}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_list_simulators_task(_input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| serde_json::to_string(&crate::simulators::list(&control)).unwrap_or_else(|e| error_json(&e.to_string())))
}

#[derive(Deserialize)]
struct SimDeleteInput {
    #[serde(default)]
    simulators: Vec<String>,
    #[serde(default)]
    runtimes: Vec<String>,
}

/// Supprime **définitivement** des simulateurs et des runtimes via `simctl`. Chaque
/// identifiant doit figurer dans la liste relue par le moteur ; un simulateur allumé ou un
/// runtime non supprimable est refusé.
///
/// Entrée JSON : `{"simulators":["<udid>"],"runtimes":["<uuid>"]}`.
/// Sortie JSON : `{"results":[{"id","removed","error"}],"cancelled"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_delete_simulators_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| {
        if input_json.is_null() {
            return error_json("pointeur d'entrée nul");
        }
        let src = match CStr::from_ptr(input_json).to_str() {
            Ok(s) => s,
            Err(_) => return error_json("entrée non-UTF-8"),
        };
        let input: SimDeleteInput = match serde_json::from_str(src) {
            Ok(v) => v,
            Err(e) => return error_json(&format!("entrée illisible : {e}")),
        };
        let mut results = crate::simulators::delete_simulators(&input.simulators, &control);
        if !input.runtimes.is_empty() {
            results.extend(crate::simulators::delete_runtimes(&input.runtimes, &control));
        }
        serde_json::json!({ "results": results, "cancelled": control.is_cancelled() }).to_string()
    })
}

// ---------------------------------------------------------------------------
// Agents de lancement (module « Démarrage »).
// ---------------------------------------------------------------------------

/// Liste les agents de lancement : de l'utilisateur, mis de côté par MacCare, et du système
/// (lecture seule). Ne modifie rien. L'entrée est ignorée (passer `{}`).
///
/// Sortie JSON : `{"agents":[{"path","label","scope":"user|disabled|system","program","orphan",
/// "loaded","running","managed_by","apple","identity","original_path"}]}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_list_agents_task(_input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| serde_json::json!({ "agents": crate::startup::list(&control) }).to_string())
}

#[derive(Deserialize)]
struct AgentActionInput {
    /// `disable` ou `enable`.
    action: String,
    path: String,
    identity: FileIdentity,
}

/// Désactive (ou réactive) un agent de l'utilisateur. Seuls les agents de `~/Library/LaunchAgents`
/// (désactivation) et ceux mis de côté par MacCare (réactivation) sont admis, relus dans une liste
/// fermée ; jamais un agent système ni Apple. Réversible ; atomique en cas d'échec.
///
/// Entrée JSON : `{"action":"disable|enable","path":"...","identity":{"device":N,"inode":N}}`.
/// Sortie JSON : `{"ok":true,"path":"<nouvel emplacement>"}` ou `{"ok":false,"error":"..."}`.
///
/// # Safety
/// `input_json` nul ou chaîne C valide ; `task` nul ou jeton valide pendant tout l'appel.
#[no_mangle]
pub unsafe extern "C" fn maccare_set_agent_task(input_json: *const c_char, task: *const MaccareTask) -> *mut c_char {
    let control = MaccareTask::control(task);
    guarded(|| {
        if input_json.is_null() {
            return error_json("pointeur d'entrée nul");
        }
        let src = match CStr::from_ptr(input_json).to_str() {
            Ok(s) => s,
            Err(_) => return error_json("entrée non-UTF-8"),
        };
        let input: AgentActionInput = match serde_json::from_str(src) {
            Ok(v) => v,
            Err(e) => return error_json(&format!("entrée illisible : {e}")),
        };
        let path = Path::new(&input.path);
        let result = match input.action.as_str() {
            "disable" => crate::startup::disable(path, input.identity, &control),
            "enable" => crate::startup::enable(path, input.identity, &control),
            other => Err(format!("action inconnue : {other}")),
        };
        match result {
            Ok(p) => serde_json::json!({ "ok": true, "path": p }).to_string(),
            Err(e) => serde_json::json!({ "ok": false, "error": e }).to_string(),
        }
    })
}

// ---------------------------------------------------------------------------
// Règles système fermées (assistant privilégié, lot 7).
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct SystemInput {
    /// Identifiant d'une règle compilée (`sys.logs.library`…). Inconnu → erreur.
    rule: String,
    #[serde(default)]
    identities: Vec<FileIdentity>,
}

unsafe fn system_input(input_json: *const c_char) -> Result<(crate::system::SystemRule, Vec<FileIdentity>), String> {
    if input_json.is_null() {
        return Err("pointeur d'entrée nul".into());
    }
    let src = CStr::from_ptr(input_json).to_str().map_err(|_| "entrée non-UTF-8")?;
    let input: SystemInput = serde_json::from_str(src).map_err(|e| format!("entrée illisible : {e}"))?;
    let id = crate::system::SystemRuleId::parse(&input.rule).ok_or("règle inconnue")?;
    Ok((id.rule(), input.identities))
}

/// Liste les éléments d'une règle système fermée. Ne modifie rien. Destinée à l'assistant
/// privilégié ; sans privilèges, elle ne voit que ce que l'utilisateur peut lire.
///
/// Entrée JSON : `{"rule":"sys.logs.rotated"}`.
/// Sortie JSON : `{"items":[{"rel_path","size_bytes","modified","identity"}],"skipped":[[chemin,raison]],
/// "truncated"}` ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL.
#[no_mangle]
pub unsafe extern "C" fn maccare_system_list(input_json: *const c_char) -> *mut c_char {
    guarded(|| match system_input(input_json) {
        Ok((rule, _)) => match crate::system::list(&rule, crate::system::Limits::default()) {
            Ok(l) => serde_json::to_string(&l).unwrap_or_else(|e| error_json(&e.to_string())),
            Err(e) => error_json(&e),
        },
        Err(e) => error_json(&e),
    })
}

/// Supprime **définitivement** les éléments d'une règle système fermée désignés par leur
/// identité. La règle est réénumérée ; seuls les éléments qui la satisfont encore, d'identité
/// inchangée, sont supprimés (relatif aux descripteurs, sans suivre de lien).
///
/// Entrée JSON : `{"rule":"...","identities":[{"device":N,"inode":N}]}`.
/// Sortie JSON : `{"removed","freed_bytes","refused":[[chemin,raison]],"not_found","truncated"}`
/// ou `{"error":"..."}`.
///
/// # Safety
/// `input_json` doit être nul ou une chaîne C valide terminée par NUL.
#[no_mangle]
pub unsafe extern "C" fn maccare_system_remove(input_json: *const c_char) -> *mut c_char {
    guarded(|| match system_input(input_json) {
        Ok((rule, ids)) => match crate::system::remove(&rule, &ids, crate::system::Limits::default()) {
            Ok(r) => serde_json::to_string(&r).unwrap_or_else(|e| error_json(&e.to_string())),
            Err(e) => error_json(&e),
        },
        Err(e) => error_json(&e),
    })
}

/// Code court et stable pour une décision, destiné à l'affichage côté UI.
fn refusal_code(decision: &Decision) -> Option<&'static str> {
    match decision {
        Decision::Allowed => None,
        Decision::Refused(r) => Some(match r {
            Refusal::SymlinkInPath(_) => "symlink",
            Refusal::StatError(_) => "stat-error",
            Refusal::OutsideScope { .. } => "outside-scope",
            Refusal::Protected(_) => "protected",
            Refusal::IdentityChanged { .. } => "identity-changed",
            Refusal::RuleMismatch(_) => "rule-mismatch",
            Refusal::NotEligible(_) => "not-eligible",
            Refusal::NoKeptCopy(_) => "no-kept-copy",
            Refusal::NotDuplicate(_) => "not-duplicate",
        }),
    }
}

/// Exécute un point d'entrée en interceptant toute panique, convertie en `{"error":...}`.
fn guarded(f: impl FnOnce() -> String) -> *mut c_char {
    let json = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f))
        .unwrap_or_else(|_| error_json("erreur interne du moteur"));
    into_c_string(json)
}

fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

fn into_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        // La chaîne contenait un NUL interne (ne devrait pas arriver avec du JSON) : renvoyer nul.
        Err(_) => std::ptr::null_mut(),
    }
}

/// Libère une chaîne renvoyée par cette couche. Nul est accepté et ignoré.
///
/// # Safety
/// `ptr` doit provenir d'un appel de cette couche (hors [`maccare_version`]) et n'être libéré
/// qu'une seule fois.
#[no_mangle]
pub unsafe extern "C" fn maccare_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}
