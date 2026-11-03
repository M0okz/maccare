//! Agents de lancement (module « Démarrage »).
//!
//! Liste les agents de l'utilisateur (`~/Library/LaunchAgents`) et, en **lecture seule**, ceux du
//! système (`/Library/LaunchAgents`, `/Library/LaunchDaemons`). Repère les **orphelins** : agents
//! dont le programme n'existe plus (app supprimée).
//!
//! Désactivation **réversible** d'un agent de l'utilisateur : arrêt par `launchctl bootout`, puis
//! déplacement du `.plist` dans un dossier de MacCare, consigné dans un registre (réactivable même
//! après relance de l'app). Garde-fous :
//! - liste fermée : le chemin est relu dans le dossier attendu (enfant direct, `.plist` ordinaire,
//!   aucun lien, identité vérifiée), jamais repris tel quel de l'appelant ;
//! - jamais un agent système ni un agent Apple (`com.apple.*`) ;
//! - opération atomique : si une étape échoue, la précédente est annulée et l'échec est dit ;
//! - à la réactivation, jamais d'écrasement d'un fichier présent à l'emplacement d'origine ;
//! - `launchctl` lancé directement, sans shell, avec des chemins absolus.

use crate::model::FileIdentity;
use crate::path_util;
use crate::safety::symlink_in_path;
use crate::walk::Control;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

const LAUNCHCTL: &str = "/bin/launchctl";
const TIMEOUT: Duration = Duration::from_secs(20);
const REGISTRY: &str = "registry.json";

/// Où vit un agent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Scope {
    /// `~/Library/LaunchAgents` : désactivable.
    User,
    /// Mis de côté par MacCare : réactivable.
    Disabled,
    /// `/Library/…` : lecture seule.
    System,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct Agent {
    pub path: PathBuf,
    pub label: String,
    pub scope: Scope,
    /// Programme lancé (`Program` ou premier élément de `ProgramArguments`).
    pub program: Option<String>,
    /// Vrai si le programme est un chemin absolu qui n'existe plus.
    pub orphan: bool,
    /// Chargé dans la session (connu de `launchctl`).
    pub loaded: bool,
    /// En cours d'exécution (a un PID).
    pub running: bool,
    /// Faux si l'état chargé/en cours est inconnu (`launchctl` illisible, ou agent du système
    /// dont l'état n'est pas visible depuis la session) : `loaded`/`running` ne valent alors rien.
    pub state_known: bool,
    /// Outil qui gère l'agent et peut le réactiver (ex. « Homebrew »).
    pub managed_by: Option<String>,
    /// Agent Apple : jamais modifiable.
    pub apple: bool,
    pub identity: Option<FileIdentity>,
    /// Pour un agent désactivé : son emplacement d'origine.
    pub original_path: Option<PathBuf>,
}

impl Agent {
    /// Vrai si MacCare accepte de le désactiver (agent de l'utilisateur, non Apple).
    pub fn can_disable(&self) -> bool {
        self.scope == Scope::User && !self.apple
    }
}

/// Une entrée du registre des agents mis de côté.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct RegistryEntry {
    /// Nom du fichier dans le dossier de MacCare.
    pub stored_as: String,
    /// Emplacement d'origine (dans `~/Library/LaunchAgents`).
    pub original_path: PathBuf,
    pub label: String,
}

/// Dossiers utilisés, injectables pour les tests.
#[derive(Debug, Clone)]
pub struct Dirs {
    pub user: PathBuf,
    pub disabled: PathBuf,
    pub system: Vec<PathBuf>,
}

impl Dirs {
    /// Dossiers réels de l'utilisateur courant.
    pub fn current() -> Option<Self> {
        let home = PathBuf::from(std::env::var("HOME").ok()?);
        Some(Dirs {
            user: home.join("Library/LaunchAgents"),
            disabled: home.join("Library/Application Support/MacCare/Disabled LaunchAgents"),
            system: vec![PathBuf::from("/Library/LaunchAgents"), PathBuf::from("/Library/LaunchDaemons")],
        })
    }
}

/// Accès à `launchctl`, remplaçable dans les tests.
pub trait Launcher {
    /// Labels chargés dans la session, avec leur PID s'ils tournent. `Err` si l'état ne peut pas
    /// être lu : on ne suppose jamais « rien n'est chargé ».
    fn loaded(&self) -> Result<HashMap<String, Option<u32>>, String>;
    fn bootout(&self, plist: &Path) -> Result<(), String>;
    fn bootstrap(&self, plist: &Path) -> Result<(), String>;
}

/// `launchctl` réel, domaine graphique de l'utilisateur courant.
pub struct Launchctl {
    control: Arc<Control>,
}

impl Launchctl {
    pub fn new(control: Arc<Control>) -> Self {
        Launchctl { control }
    }

    fn domain() -> String {
        format!("gui/{}", unsafe { libc::getuid() })
    }

    fn with_plist(&self, verb: &str, plist: &Path) -> Result<(), String> {
        let p = plist.to_str().ok_or("chemin non-UTF-8")?;
        // Chemin absolu uniquement : jamais une valeur prise pour une option.
        if !p.starts_with('/') {
            return Err("chemin non absolu".into());
        }
        crate::proc::run(Path::new(LAUNCHCTL), &[verb, &Self::domain(), p], TIMEOUT, &self.control).map(|_| ())
    }
}

impl Launcher for Launchctl {
    fn loaded(&self) -> Result<HashMap<String, Option<u32>>, String> {
        let out = crate::proc::run(Path::new(LAUNCHCTL), &["list"], TIMEOUT, &self.control)?;
        Ok(parse_launchctl_list(&out))
    }
    fn bootout(&self, plist: &Path) -> Result<(), String> {
        self.with_plist("bootout", plist)
    }
    fn bootstrap(&self, plist: &Path) -> Result<(), String> {
        self.with_plist("bootstrap", plist)
    }
}

/// Analyse la sortie de `launchctl list` (« PID  Status  Label »).
pub fn parse_launchctl_list(out: &str) -> HashMap<String, Option<u32>> {
    out.lines()
        .skip(1)
        .filter_map(|l| {
            let mut cols = l.split('\t');
            let pid = cols.next()?.trim();
            let _status = cols.next()?;
            let label = cols.next()?.trim();
            (!label.is_empty()).then(|| (label.to_string(), pid.parse::<u32>().ok()))
        })
        .collect()
}

/// Lecture d'un plist d'agent : (label, programme). `None` si le fichier n'est pas un plist lisible.
fn read_agent_plist(path: &Path) -> Option<(Option<String>, Option<String>)> {
    let bytes = std::fs::read(path).ok()?;
    let value = plist::Value::from_reader(std::io::Cursor::new(bytes)).ok()?;
    let dict = value.as_dictionary()?;
    let label = dict.get("Label").and_then(|v| v.as_string()).map(str::to_string);
    let program = dict
        .get("Program")
        .and_then(|v| v.as_string())
        .map(str::to_string)
        .or_else(|| {
            dict.get("ProgramArguments")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_string())
                .map(str::to_string)
        });
    Some((label, program))
}

fn is_plain_plist(path: &Path) -> bool {
    path.extension().is_some_and(|e| e == "plist")
        && matches!(symlink_in_path(path), Ok(false))
        && std::fs::symlink_metadata(path).is_ok_and(|m| m.is_file())
}

/// Vrai si le programme est **certainement** absent : chemin absolu, hors volume amovible
/// (`/Volumes/…` peut être simplement démonté), et le premier composant manquant est absent d'un
/// dossier qu'on a pu lire. Une erreur de droits (TCC) n'en fait jamais un orphelin.
pub fn program_missing(program: &str) -> bool {
    let p = Path::new(program);
    if !p.is_absolute() || p.starts_with("/Volumes") {
        return false;
    }
    match std::fs::metadata(p) {
        Ok(_) => return false,
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => return false,
        Err(_) => {}
    }
    // Remonte au plus proche ancêtre existant : il doit être lisible, et ne pas contenir l'élément.
    let mut child = p;
    while let Some(parent) = child.parent() {
        match std::fs::metadata(parent) {
            Ok(md) if md.is_dir() => {
                let Ok(rd) = std::fs::read_dir(parent) else { return false };
                let name = child.file_name();
                return match rd.flatten().find(|e| Some(e.file_name().as_os_str()) == name) {
                    None => true,
                    // Lien cassé (sa cible n'existe plus, `metadata` l'a dit) : programme inatteignable,
                    // sauf si la cible est sur un volume peut-être simplement démonté.
                    Some(e) => {
                        e.file_type().is_ok_and(|t| t.is_symlink())
                            && std::fs::read_link(e.path()).is_ok_and(|t| !t.starts_with("/Volumes"))
                    }
                };
            }
            Ok(_) => return false,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => child = parent,
            Err(_) => return false,
        }
    }
    false
}

fn managed_by(label: &str) -> Option<String> {
    label.starts_with("homebrew.mxcl.").then(|| "Homebrew".to_string())
}

fn describe(path: &Path, scope: Scope, loaded: Option<&HashMap<String, Option<u32>>>) -> Agent {
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let (label, program) = read_agent_plist(path).unwrap_or((None, None));
    let apple = stem.starts_with("com.apple.") || label.as_deref().is_some_and(|l| l.starts_with("com.apple."));
    let label = label.unwrap_or(stem);
    let orphan = program.as_deref().is_some_and(program_missing);
    // L'état des agents du système n'est pas visible depuis la session : on n'en affiche aucun.
    let loaded = if scope == Scope::System { None } else { loaded };
    let state = loaded.and_then(|l| l.get(&label));
    Agent {
        path: path.to_path_buf(),
        apple,
        managed_by: managed_by(&label),
        loaded: state.is_some(),
        running: state.is_some_and(|pid| pid.is_some()),
        state_known: loaded.is_some(),
        label,
        scope,
        program,
        orphan,
        identity: FileIdentity::of_path(path).ok(),
        original_path: None,
    }
}

fn plists_in(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|rd| rd.flatten().map(|e| e.path()).filter(|p| is_plain_plist(p)).collect())
        .unwrap_or_default();
    v.sort();
    v
}

pub fn read_registry(dirs: &Dirs) -> Vec<RegistryEntry> {
    std::fs::read(dirs.disabled.join(REGISTRY))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}

fn write_registry(dirs: &Dirs, entries: &[RegistryEntry]) -> Result<(), String> {
    let json = serde_json::to_vec_pretty(entries).map_err(|e| e.to_string())?;
    let tmp = dirs.disabled.join(format!("{REGISTRY}.tmp"));
    std::fs::write(&tmp, json).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, dirs.disabled.join(REGISTRY)).map_err(|e| e.to_string())
}

/// Tous les agents : de l'utilisateur, mis de côté par MacCare, et du système (lecture seule).
pub fn list_in(dirs: &Dirs, launcher: &dyn Launcher) -> Vec<Agent> {
    let loaded = launcher.loaded().ok();
    let loaded = loaded.as_ref();
    let mut out: Vec<Agent> = plists_in(&dirs.user).iter().map(|p| describe(p, Scope::User, loaded)).collect();
    for entry in read_registry(dirs) {
        let stored = dirs.disabled.join(&entry.stored_as);
        if is_plain_plist(&stored) {
            let mut a = describe(&stored, Scope::Disabled, loaded);
            a.original_path = Some(entry.original_path);
            out.push(a);
        }
    }
    for dir in &dirs.system {
        out.extend(plists_in(dir).iter().map(|p| describe(p, Scope::System, loaded)));
    }
    out
}

/// Agents de l'utilisateur courant.
pub fn list(control: &Arc<Control>) -> Vec<Agent> {
    match Dirs::current() {
        Some(d) => list_in(&d, &Launchctl::new(Arc::clone(control))),
        None => Vec::new(),
    }
}

/// Retrouve dans la liste fermée l'agent désigné par l'appelant. Rejette tout le reste.
fn closed_list_match(dirs: &Dirs, path: &Path, identity: FileIdentity, launcher: &dyn Launcher, scope: Scope) -> Result<Agent, String> {
    let norm = path_util::lexical_normalize(path);
    let agent = list_in(dirs, launcher)
        .into_iter()
        .find(|a| a.path == norm && a.scope == scope)
        .ok_or("not-listed")?;
    if agent.apple {
        return Err("apple".into());
    }
    if !is_plain_plist(&agent.path) {
        return Err("symlink".into());
    }
    if agent.identity != Some(identity) {
        return Err("identity-changed".into());
    }
    Ok(agent)
}

/// Désactive un agent de l'utilisateur : arrêt s'il est chargé, puis mise de côté et inscription
/// au registre. En cas d'échec d'une étape, l'état d'avant est rétabli. Renvoie le nouvel emplacement.
pub fn disable_in(dirs: &Dirs, path: &Path, identity: FileIdentity, launcher: &dyn Launcher) -> Result<PathBuf, String> {
    // Sans état fiable, on ne sait pas s'il faut l'arrêter : déplacer le fichier seul laisserait
    // tourner un service présenté comme désactivé. Refus.
    let loaded = launcher.loaded().map_err(|_| "launchctl-unknown".to_string())?;
    let mut agent = closed_list_match(dirs, path, identity, launcher, Scope::User)?;
    agent.loaded = loaded.contains_key(&agent.label);
    std::fs::create_dir_all(&dirs.disabled).map_err(|e| e.to_string())?;

    // Nom de rangement libre (jamais d'écrasement d'un agent déjà mis de côté).
    let name = agent.path.file_name().ok_or("not-listed")?.to_string_lossy().into_owned();
    let mut stored_as = name.clone();
    let mut n = 1;
    while dirs.disabled.join(&stored_as).exists() {
        n += 1;
        stored_as = format!("{n}-{name}");
    }
    let stored = dirs.disabled.join(&stored_as);

    if agent.loaded {
        launcher.bootout(&agent.path).map_err(|e| format!("arrêt impossible : {e}"))?;
    }
    if let Err(e) = std::fs::rename(&agent.path, &stored) {
        if agent.loaded {
            let _ = launcher.bootstrap(&agent.path); // remise en route : rien n'a bougé
        }
        return Err(format!("déplacement impossible, agent remis en route : {e}"));
    }
    let mut registry = read_registry(dirs);
    registry.push(RegistryEntry { stored_as, original_path: agent.path.clone(), label: agent.label.clone() });
    if let Err(e) = write_registry(dirs, &registry) {
        // Sans registre, la réactivation serait impossible : on annule tout.
        let _ = std::fs::rename(&stored, &agent.path);
        if agent.loaded {
            let _ = launcher.bootstrap(&agent.path);
        }
        return Err(format!("registre illisible, rien n'a été changé : {e}"));
    }
    Ok(stored)
}

/// Réactive un agent mis de côté par MacCare : retour à son emplacement d'origine (refusé si un
/// fichier y existe déjà), puis chargement. En cas d'échec du chargement, il reste mis de côté.
pub fn enable_in(dirs: &Dirs, path: &Path, identity: FileIdentity, launcher: &dyn Launcher) -> Result<PathBuf, String> {
    let agent = closed_list_match(dirs, path, identity, launcher, Scope::Disabled)?;
    let original = agent.original_path.clone().ok_or("not-listed")?;
    // L'emplacement d'origine doit rester un enfant direct du dossier des agents.
    if path_util::lexical_normalize(&original).parent() != Some(path_util::lexical_normalize(&dirs.user).as_path()) {
        return Err("outside-scope".into());
    }
    if std::fs::symlink_metadata(&original).is_ok() {
        return Err("occupied".into());
    }
    std::fs::create_dir_all(&dirs.user).map_err(|e| e.to_string())?;
    std::fs::rename(&agent.path, &original).map_err(|e| e.to_string())?;
    if let Err(e) = launcher.bootstrap(&original) {
        let _ = std::fs::rename(&original, &agent.path);
        return Err(format!("chargement impossible, agent laissé désactivé : {e}"));
    }
    let stored_as = agent.path.file_name().map(|n| n.to_string_lossy().into_owned());
    let registry: Vec<RegistryEntry> = read_registry(dirs)
        .into_iter()
        .filter(|e| Some(&e.stored_as) != stored_as.as_ref())
        .collect();
    let _ = write_registry(dirs, &registry);
    Ok(original)
}

/// Désactive un agent de l'utilisateur courant.
pub fn disable(path: &Path, identity: FileIdentity, control: &Arc<Control>) -> Result<PathBuf, String> {
    let dirs = Dirs::current().ok_or("HOME indéfini")?;
    disable_in(&dirs, path, identity, &Launchctl::new(Arc::clone(control)))
}

/// Réactive un agent mis de côté par MacCare.
pub fn enable(path: &Path, identity: FileIdentity, control: &Arc<Control>) -> Result<PathBuf, String> {
    let dirs = Dirs::current().ok_or("HOME indéfini")?;
    enable_in(&dirs, path, identity, &Launchctl::new(Arc::clone(control)))
}
