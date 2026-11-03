//! Simulateurs et runtimes Xcode (module « Simulateurs », outils pour développeurs).
//!
//! Tout passe par l'outil d'Apple, `simctl` : on ne supprime **jamais** un dossier de simulateur
//! à la main (CoreSimulator garde son propre registre, qu'un `rm` désynchroniserait).
//!
//! `simctl` est localisé via `xcode-select -p` puis lancé directement, jamais par `xcrun` : sur un
//! Mac sans outils de développement, `xcrun` peut ouvrir la fenêtre système d'installation. Sans
//! `simctl` présent, le module répond simplement « Xcode absent ».
//!
//! Garde-fous :
//! - **liste fermée** : un UDID ou un runtime n'est supprimé que s'il figure dans une liste
//!   relue juste avant, auprès de `simctl` ;
//! - jamais un simulateur **allumé** (état autre que `Shutdown`), jamais un runtime marqué non
//!   supprimable ; jamais le « device set » entier ;
//! - les identifiants transmis à `simctl` doivent avoir la forme d'un UUID (pas d'option glissée) ;
//! - chaque appel est borné dans le temps et annulable : un service CoreSimulator qui ne répond
//!   pas ne fige pas l'app.

use crate::walk::{self, Budget, Control};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

const XCODE_SELECT: &str = "/usr/bin/xcode-select";
const LIST_TIMEOUT: Duration = Duration::from_secs(60);
const DELETE_TIMEOUT: Duration = Duration::from_secs(300);

/// Un simulateur.
#[derive(Debug, Clone, serde::Serialize, PartialEq)]
pub struct Simulator {
    pub udid: String,
    pub name: String,
    /// Système lisible, ex. « iOS 17.5 ».
    pub runtime: String,
    pub runtime_identifier: String,
    /// `Shutdown`, `Booted`…
    pub state: String,
    /// Faux si son runtime n'est plus installé (simulateur inutilisable).
    pub available: bool,
    /// Dernière utilisation (ISO 8601), si connue.
    pub last_used: Option<String>,
    /// Espace occupé par ses données (mesuré par le moteur).
    pub size_bytes: u64,
}

/// Un runtime de simulateur téléchargé (image système iOS, watchOS…).
#[derive(Debug, Clone, serde::Serialize, PartialEq)]
pub struct SimRuntime {
    pub identifier: String,
    pub name: String,
    pub runtime_identifier: String,
    pub size_bytes: u64,
    pub deletable: bool,
    pub last_used: Option<String>,
    /// Simulateurs qui l'utilisent (ils deviendront inutilisables s'il est supprimé).
    pub devices: usize,
}

#[derive(Debug, Default, serde::Serialize)]
pub struct SimOutcome {
    /// Faux si Xcode (ou ses outils) n'est pas installé.
    pub xcode: bool,
    pub simulators: Vec<Simulator>,
    pub runtimes: Vec<SimRuntime>,
    pub warnings: Vec<String>,
    pub cancelled: bool,
}

/// « com.apple.CoreSimulator.SimRuntime.iOS-17-5 » → « iOS 17.5 ».
pub fn runtime_name(identifier: &str) -> String {
    let tail = identifier.rsplit('.').next().unwrap_or(identifier);
    match tail.split_once('-') {
        Some((os, version)) => format!("{os} {}", version.replace('-', ".")),
        None => tail.to_string(),
    }
}

/// Vrai si `s` a la forme d'un UUID (8-4-4-4-12 hexadécimal).
pub fn is_uuid(s: &str) -> bool {
    let parts: Vec<&str> = s.split('-').collect();
    parts.len() == 5
        && parts.iter().zip([8, 4, 4, 4, 12]).all(|(p, n)| p.len() == n && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// Simulateurs décrits par `simctl list devices --json` (tailles à 0, mesurées ensuite).
pub fn parse_devices(json: &str) -> Result<Vec<Simulator>, String> {
    let v: Value = serde_json::from_str(json).map_err(|e| format!("réponse simctl illisible : {e}"))?;
    let devices = v.get("devices").and_then(Value::as_object).ok_or("réponse simctl sans « devices »")?;
    let mut out = Vec::new();
    for (runtime_id, list) in devices {
        for d in list.as_array().into_iter().flatten() {
            let udid = d.get("udid").and_then(Value::as_str).unwrap_or_default();
            if !is_uuid(udid) {
                continue;
            }
            out.push(Simulator {
                udid: udid.to_string(),
                name: d.get("name").and_then(Value::as_str).unwrap_or("Simulateur").to_string(),
                runtime: runtime_name(runtime_id),
                runtime_identifier: runtime_id.clone(),
                state: d.get("state").and_then(Value::as_str).unwrap_or("Unknown").to_string(),
                available: d.get("isAvailable").and_then(Value::as_bool).unwrap_or(false),
                last_used: d
                    .get("lastUsedAt")
                    .or_else(|| d.get("lastBootedAt"))
                    .and_then(Value::as_str)
                    .map(str::to_string),
                size_bytes: 0,
            });
        }
    }
    Ok(out)
}

/// Runtimes décrits par `simctl runtime list -j`.
pub fn parse_runtimes(json: &str) -> Result<Vec<SimRuntime>, String> {
    let v: Value = serde_json::from_str(json).map_err(|e| format!("réponse simctl illisible : {e}"))?;
    let map = v.as_object().ok_or("réponse simctl inattendue")?;
    let mut out = Vec::new();
    for (key, r) in map {
        let id = r.get("identifier").and_then(Value::as_str).unwrap_or(key);
        if !is_uuid(id) {
            continue;
        }
        let runtime_identifier = r.get("runtimeIdentifier").and_then(Value::as_str).unwrap_or_default().to_string();
        out.push(SimRuntime {
            identifier: id.to_string(),
            name: runtime_name(&runtime_identifier),
            runtime_identifier,
            size_bytes: r.get("sizeBytes").and_then(Value::as_u64).unwrap_or(0),
            deletable: r.get("deletable").and_then(Value::as_bool).unwrap_or(false),
            last_used: r.get("lastUsedAt").and_then(Value::as_str).map(str::to_string),
            devices: 0,
        });
    }
    Ok(out)
}

/// `simctl` d'un dossier développeur donné, s'il y est vraiment (fichier ordinaire).
pub fn simctl_in(developer_dir: &Path) -> Option<PathBuf> {
    let simctl = developer_dir.join("usr/bin/simctl");
    std::fs::metadata(&simctl).is_ok_and(|m| m.is_file()).then_some(simctl)
}

/// Localise `simctl` sans jamais déclencher l'installation des outils : `DEVELOPER_DIR` s'il est
/// défini, sinon `xcode-select -p`. `None` si Xcode (et donc `simctl`) n'est pas installé.
pub fn simctl_path() -> Option<PathBuf> {
    let dir = match std::env::var_os("DEVELOPER_DIR").filter(|v| !v.is_empty()) {
        Some(d) => PathBuf::from(d),
        None => {
            let out = Command::new(XCODE_SELECT)
                .arg("-p")
                .stdin(Stdio::null())
                .stderr(Stdio::null())
                .output()
                .ok()?;
            if !out.status.success() {
                return None;
            }
            PathBuf::from(String::from_utf8_lossy(&out.stdout).trim())
        }
    };
    simctl_in(&dir)
}

/// Lance `simctl` avec ces arguments (jamais via un shell), borné dans le temps et annulable.
fn run(simctl: &Path, args: &[&str], timeout: Duration, control: &Arc<Control>) -> Result<String, String> {
    crate::proc::run(simctl, args, timeout, control).map_err(|e| match e.as_str() {
        "introuvable" => "simctl indisponible".to_string(),
        "ne répond pas" => "simctl ne répond pas".to_string(),
        _ => e,
    })
}

/// Dossier de données d'un simulateur, reconstruit à partir de son UDID (jamais repris de la
/// réponse de l'outil).
fn device_dir(udid: &str) -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join("Library/Developer/CoreSimulator/Devices").join(udid))
}

fn list_devices(simctl: &Path, control: &Arc<Control>) -> Result<Vec<Simulator>, String> {
    parse_devices(&run(simctl, &["list", "devices", "--json"], LIST_TIMEOUT, control)?)
}

fn list_runtimes(simctl: &Path, control: &Arc<Control>) -> Result<Vec<SimRuntime>, String> {
    parse_runtimes(&run(simctl, &["runtime", "list", "-j"], LIST_TIMEOUT, control)?)
}

/// Liste les simulateurs (avec la taille de leurs données) et les runtimes. Ne supprime rien.
pub fn list(control: &Arc<Control>) -> SimOutcome {
    let mut out = SimOutcome::default();
    let Some(simctl) = simctl_path() else {
        return out; // Xcode absent : rien n'est lancé
    };
    let mut sims = match list_devices(&simctl, control) {
        Ok(s) => s,
        Err(e) => {
            out.cancelled = control.is_cancelled();
            if !out.cancelled {
                out.warnings.push(e);
            }
            return out;
        }
    };
    out.xcode = true;
    match list_runtimes(&simctl, control) {
        Ok(r) => out.runtimes = r,
        // Outils plus anciens sans « simctl runtime » : on garde au moins les simulateurs.
        Err(e) if !control.is_cancelled() => out.warnings.push(format!("runtimes : {e}")),
        Err(_) => {}
    }

    let dirs: Vec<PathBuf> = sims.iter().filter_map(|s| device_dir(&s.udid)).collect();
    let sizes = walk::measure_paths_with(&dirs, Budget::new(Duration::from_secs(60)), control);
    for (s, m) in sims.iter_mut().zip(sizes) {
        s.size_bytes = m.bytes;
    }
    for r in &mut out.runtimes {
        r.devices = sims.iter().filter(|s| s.runtime_identifier == r.runtime_identifier).count();
    }
    sims.sort_by_key(|s| std::cmp::Reverse(s.size_bytes));
    out.simulators = sims;
    out.cancelled = control.is_cancelled();
    out
}

/// Issue de la suppression d'un simulateur ou d'un runtime.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DeleteResult {
    pub id: String,
    pub removed: bool,
    /// Code court si refusé ou en échec : `not-listed`, `booted`, `not-deletable`, `invalid-id`,
    /// sinon le message de l'outil.
    pub error: Option<String>,
}

fn refuse(id: &str, code: &str) -> DeleteResult {
    DeleteResult { id: id.to_string(), removed: false, error: Some(code.to_string()) }
}

/// Supprime des simulateurs par `simctl delete`, après relecture de la liste : seuls ceux
/// qui y figurent **et sont éteints** sont supprimés. Supprime définitivement leurs données.
pub fn delete_simulators(udids: &[String], control: &Arc<Control>) -> Vec<DeleteResult> {
    let Some(simctl) = simctl_path() else {
        return udids.iter().map(|u| refuse(u, "xcode-absent")).collect();
    };
    let fresh = match list_devices(&simctl, control) {
        Ok(f) => f,
        Err(e) => return udids.iter().map(|u| refuse(u, &e)).collect(),
    };
    udids
        .iter()
        .map(|udid| {
            if !is_uuid(udid) {
                return refuse(udid, "invalid-id");
            }
            let Some(sim) = fresh.iter().find(|s| s.udid.eq_ignore_ascii_case(udid)) else {
                return refuse(udid, "not-listed");
            };
            if sim.state != "Shutdown" {
                return refuse(udid, "booted");
            }
            if control.is_cancelled() {
                return refuse(udid, "annulé");
            }
            match run(&simctl, &["delete", &sim.udid], DELETE_TIMEOUT, control) {
                Ok(_) => DeleteResult { id: udid.clone(), removed: true, error: None },
                Err(e) => refuse(udid, &e),
            }
        })
        .collect()
}

/// Supprime des runtimes par `simctl runtime delete`, après relecture : seuls ceux qui y
/// figurent **et sont marqués supprimables** le sont.
pub fn delete_runtimes(ids: &[String], control: &Arc<Control>) -> Vec<DeleteResult> {
    let Some(simctl) = simctl_path() else {
        return ids.iter().map(|i| refuse(i, "xcode-absent")).collect();
    };
    let fresh = match list_runtimes(&simctl, control) {
        Ok(f) => f,
        Err(e) => return ids.iter().map(|i| refuse(i, &e)).collect(),
    };
    ids.iter()
        .map(|id| {
            if !is_uuid(id) {
                return refuse(id, "invalid-id");
            }
            let Some(rt) = fresh.iter().find(|r| r.identifier.eq_ignore_ascii_case(id)) else {
                return refuse(id, "not-listed");
            };
            if !rt.deletable {
                return refuse(id, "not-deletable");
            }
            if control.is_cancelled() {
                return refuse(id, "annulé");
            }
            match run(&simctl, &["runtime", "delete", &rt.identifier], DELETE_TIMEOUT, control) {
                Ok(_) => DeleteResult { id: id.clone(), removed: true, error: None },
                Err(e) => refuse(id, &e),
            }
        })
        .collect()
}
