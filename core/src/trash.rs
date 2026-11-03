//! Corbeilles (module « Corbeilles »). **Seule suppression définitive de l'application.**
//!
//! Le moteur repère lui-même les corbeilles de l'utilisateur — `~/.Trash` et le dossier
//! `.Trashes/<uid>` de chaque volume monté — et n'en vide **aucune autre** : un chemin demandé
//! par l'appelant qui ne figure pas dans cette liste fermée est refusé. Chaque corbeille est
//! re-vérifiée au moment du vidage (pas de lien symbolique dans le chemin, identité inchangée
//! depuis l'affichage).
//!
//! L'affichage fournit une **empreinte du contenu** (identité de chaque élément de premier niveau).
//! Au vidage, le moteur relit le contenu : s'il ne correspond plus à cette empreinte (un fichier
//! ajouté entre-temps depuis le Finder, par exemple), la corbeille est refusée sans rien supprimer.
//! Sinon, il retire **exactement** les éléments vérifiés, jamais un élément arrivé après.
//!
//! Le vidage retire les enfants directs un par un ([`std::fs::remove_dir_all`] ne suit pas les
//! liens symboliques : un lien est supprimé, sa cible jamais touchée). Les éléments verrouillés
//! ou protégés sont signalés, jamais forcés. Annulable entre deux éléments.

use crate::model::FileIdentity;
use crate::path_util;
use crate::safety::symlink_in_path;
use crate::walk::{self, Budget, Control};
use sha2::{Digest, Sha256};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

/// Budget de mesure de toutes les corbeilles.
pub const MEASURE_BUDGET: Duration = Duration::from_secs(30);

/// Une corbeille repérée.
#[derive(Debug, Clone, serde::Serialize)]
pub struct TrashBin {
    pub path: PathBuf,
    /// « Corbeille » pour celle du dossier personnel, sinon le nom du volume.
    pub label: String,
    pub identity: FileIdentity,
    /// Éléments de premier niveau (hors `.DS_Store`).
    pub items: usize,
    pub size_bytes: u64,
    /// Faux si la mesure n'a pas pu aller au bout (taille minorée).
    pub measured: bool,
    /// Faux si le contenu n'a pas pu être lu (Accès complet au disque manquant, par exemple) :
    /// la corbeille n'est alors pas « vide », elle est inconnue.
    pub readable: bool,
    /// Empreinte du contenu affiché, à renvoyer telle quelle pour le vidage (vide si illisible).
    pub snapshot: String,
}

/// Un élément de premier niveau d'une corbeille, tel qu'énuméré (sans suivre de lien).
struct Child {
    path: PathBuf,
    name: std::ffi::OsString,
    dev: u64,
    ino: u64,
}

fn children(dir: &Path) -> std::io::Result<Vec<Child>> {
    let mut out = Vec::new();
    for e in std::fs::read_dir(dir)?.flatten() {
        let Ok(md) = e.metadata() else { continue }; // ne suit pas les liens
        out.push(Child { path: e.path(), name: e.file_name(), dev: md.dev(), ino: md.ino() });
    }
    Ok(out)
}

/// Empreinte d'un contenu : SHA-256 des (nom, volume, inode) triés. `.DS_Store`, réécrit par le
/// Finder à chaque affichage, n'y entre pas.
fn snapshot_of(kids: &[Child]) -> String {
    let mut lines: Vec<Vec<u8>> = kids
        .iter()
        .filter(|c| c.name != ".DS_Store")
        .map(|c| {
            let mut l = c.name.as_encoded_bytes().to_vec();
            l.extend_from_slice(format!("\0{}\0{}\n", c.dev, c.ino).as_bytes());
            l
        })
        .collect();
    lines.sort();
    let mut h = Sha256::new();
    for l in &lines {
        h.update(l);
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Vrai si `path` est un dossier réel (pas un lien), sans lien symbolique dans ses ancêtres,
/// appartenant à `uid`.
fn is_owned_real_dir(path: &Path, uid: u32) -> bool {
    matches!(symlink_in_path(path), Ok(false))
        && std::fs::symlink_metadata(path).is_ok_and(|m| m.is_dir() && m.uid() == uid)
}

fn current_uid() -> u32 {
    unsafe { libc::getuid() }
}

/// Corbeilles candidates sous `home` et `volumes`, pour l'utilisateur `uid`. Les volumes
/// présentés par un lien (le disque de démarrage dans `/Volumes`) sont ignorés : leur corbeille
/// est celle du dossier personnel.
pub fn locate_in(home: &Path, volumes: &Path, uid: u32) -> Vec<(PathBuf, String)> {
    let mut found = Vec::new();
    let home_trash = home.join(".Trash");
    if is_owned_real_dir(&home_trash, uid) {
        found.push((path_util::lexical_normalize(&home_trash), "Corbeille".to_string()));
    }
    if let Ok(entries) = std::fs::read_dir(volumes) {
        let mut vols: Vec<_> = entries.flatten().collect();
        vols.sort_by_key(|e| e.file_name());
        for vol in vols {
            if vol.file_type().map(|t| t.is_symlink()).unwrap_or(true) {
                continue;
            }
            let bin = vol.path().join(".Trashes").join(uid.to_string());
            if is_owned_real_dir(&bin, uid) {
                found.push((path_util::lexical_normalize(&bin), vol.file_name().to_string_lossy().into_owned()));
            }
        }
    }
    found
}

/// Corbeilles de l'utilisateur courant.
pub fn locate() -> Vec<(PathBuf, String)> {
    let Ok(home) = std::env::var("HOME") else { return Vec::new() };
    locate_in(Path::new(&home), Path::new("/Volumes"), current_uid())
}

/// Éléments de premier niveau, ou `None` si le dossier est illisible.
fn count_items(dir: &Path) -> Option<usize> {
    std::fs::read_dir(dir)
        .ok()
        .map(|rd| rd.flatten().filter(|e| e.file_name() != ".DS_Store").count())
}

/// Mesure les corbeilles données (toutes ensemble, sur le pool partagé).
pub fn measure(located: &[(PathBuf, String)], budget: Budget, control: &Arc<Control>) -> Vec<TrashBin> {
    let roots: Vec<PathBuf> = located.iter().map(|(p, _)| p.clone()).collect();
    let sizes = walk::measure_paths_with(&roots, budget, control);
    located
        .iter()
        .zip(sizes)
        .filter_map(|((path, label), m)| {
            let items = count_items(path);
            let snapshot = children(path).map(|k| snapshot_of(&k)).unwrap_or_default();
            Some(TrashBin {
                snapshot,
                identity: FileIdentity::of_path(path).ok()?,
                items: items.unwrap_or(0),
                readable: items.is_some(),
                path: path.clone(),
                label: label.clone(),
                size_bytes: m.bytes,
                measured: m.complete && items.is_some(),
            })
        })
        .collect()
}

/// Issue du vidage d'une corbeille.
#[derive(Debug, Clone, serde::Serialize)]
pub struct EmptyResult {
    pub path: PathBuf,
    /// Code de refus de la corbeille entière (`not-a-trash`, `identity-changed`, `symlink`,
    /// `content-changed`). Rien n'est supprimé en cas de refus.
    pub refusal: Option<&'static str>,
    pub removed: usize,
    /// Octets alloués libérés (mesure avant − mesure après).
    pub freed_bytes: u64,
    /// Éléments non retirés, avec la raison.
    pub failures: Vec<(PathBuf, String)>,
}

/// Une corbeille à vider, telle qu'affichée à l'utilisateur.
#[derive(Debug, Clone)]
pub struct EmptyRequest {
    pub path: PathBuf,
    pub identity: FileIdentity,
    /// Empreinte rendue par [`measure`] : le contenu doit être exactement celui-là.
    pub snapshot: String,
}

/// Vide les corbeilles demandées, chacune devant figurer dans `located` (liste fermée) avec
/// l'identité et le contenu affichés. Supprime **définitivement**.
pub fn empty_in(
    located: &[(PathBuf, String)],
    requested: &[EmptyRequest],
    uid: u32,
    control: &Arc<Control>,
) -> Vec<EmptyResult> {
    requested
        .iter()
        .map(|EmptyRequest { path, identity, snapshot }| {
            let norm = path_util::lexical_normalize(path);
            let mut result = EmptyResult {
                path: path.clone(),
                refusal: None,
                removed: 0,
                freed_bytes: 0,
                failures: Vec::new(),
            };
            if !located.iter().any(|(p, _)| *p == norm) {
                result.refusal = Some("not-a-trash");
                return result;
            }
            if !is_owned_real_dir(&norm, uid) {
                result.refusal = Some("symlink");
                return result;
            }
            if FileIdentity::of_path(&norm).ok() != Some(*identity) {
                result.refusal = Some("identity-changed");
                return result;
            }

            let budget = Budget::new(MEASURE_BUDGET);
            let before = walk::measure_path(&norm, budget).bytes;
            let entries = match children(&norm) {
                Ok(k) => k,
                Err(e) => {
                    result.failures.push((norm.clone(), e.to_string()));
                    return result;
                }
            };
            // Le contenu doit être exactement celui que l'utilisateur a confirmé.
            if snapshot.is_empty() || snapshot_of(&entries) != *snapshot {
                result.refusal = Some("content-changed");
                return result;
            }
            let bin_dev = std::fs::symlink_metadata(&norm).map(|m| m.dev()).unwrap_or(0);
            for child in entries {
                if control.is_cancelled() {
                    break;
                }
                let entry = child.path;
                // Remplacé depuis l'énumération : on ne supprime que ce qui a été vérifié.
                let same = std::fs::symlink_metadata(&entry).is_ok_and(|m| m.dev() == child.dev && m.ino() == child.ino);
                if !same {
                    result.failures.push((entry, "modifié depuis l'affichage : non touché".into()));
                    continue;
                }
                // Jamais au-delà du volume de la corbeille (un montage placé dedans, par exemple).
                if crosses_volume(&entry, bin_dev) {
                    result.failures.push((entry, "autre volume : non touché".into()));
                    continue;
                }
                match remove_entry(&entry) {
                    Ok(()) => result.removed += 1,
                    Err(e) => result.failures.push((entry, describe(&e))),
                }
                control.add_progress(1, 0);
            }
            let after = walk::measure_path(&norm, budget).bytes;
            result.freed_bytes = before.saturating_sub(after);
            result
        })
        .collect()
}

/// Vide des corbeilles de l'utilisateur courant (liste fermée de [`locate`]).
pub fn empty(requested: &[EmptyRequest], control: &Arc<Control>) -> Vec<EmptyResult> {
    empty_in(&locate(), requested, current_uid(), control)
}

/// Vrai si `entry` est sur un autre volume que `dev`, ou si c'est un dossier qui en contient un
/// (point de montage à l'intérieur). Parcours sans suivre de lien ; une erreur de lecture compte
/// comme un franchissement (fail-closed).
fn crosses_volume(entry: &Path, dev: u64) -> bool {
    let Ok(md) = std::fs::symlink_metadata(entry) else { return true };
    if md.dev() != dev {
        return true;
    }
    if !md.is_dir() {
        return false;
    }
    let mut stack = vec![entry.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&dir) else { return true };
        for e in rd.flatten() {
            let Ok(m) = e.metadata() else { return true }; // ne suit pas les liens
            if m.dev() != dev {
                return true;
            }
            if m.is_dir() {
                stack.push(e.path());
            }
        }
    }
    false
}

/// Retire une entrée **sans suivre** de lien : un lien ou un fichier est délié, un dossier réel
/// est retiré récursivement (sans suivre les liens qu'il contient).
fn remove_entry(path: &Path) -> std::io::Result<()> {
    let md = std::fs::symlink_metadata(path)?;
    if md.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    }
}

/// Raison lisible d'un échec de suppression.
fn describe(e: &std::io::Error) -> String {
    match e.raw_os_error() {
        Some(libc::EPERM) => "verrouillé ou protégé".into(),
        Some(libc::EACCES) => "accès refusé".into(),
        Some(libc::EBUSY) => "en cours d'utilisation".into(),
        _ => e.to_string(),
    }
}
