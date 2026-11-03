//! Règles système fermées, pour l'assistant privilégié (lot 7, voir
//! `docs/architecture.md`).
//!
//! Ce module est le **seul** code que l'assistant exécute avec les droits administrateur. Il ne
//! sait faire que deux choses, sur des règles compilées ici (jamais fournies par l'appelant) :
//! lister les éléments d'une règle, et supprimer ceux d'entre eux que l'appelant désigne par leur
//! identité `(volume, inode)`.
//!
//! Garde-fous, propres au contexte privilégié :
//! - **aucun chemin complet** n'est ouvert sous la racine : parcours et suppression se font
//!   relativement à des descripteurs de dossier (`openat`, `fstatat`, `unlinkat`), sans jamais
//!   suivre de lien (`O_NOFOLLOW`, `AT_SYMLINK_NOFOLLOW`) ; un lien substitué entre deux étapes ne
//!   peut pas rediriger une suppression ;
//! - l'identité d'un fichier est revérifiée **juste avant** `unlinkat`, dans le même dossier ouvert ;
//! - même volume que la racine ; dossiers inscriptibles par tous refusés ; dossiers inscriptibles
//!   par leur groupe seulement si c'est un groupe système ; propriétaires système uniquement ;
//! - fichiers verrouillés (drapeaux immuables ou en ajout seul) signalés, jamais forcés ;
//! - nombre d'éléments et durée bornés.

use crate::model::FileIdentity;
use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// Identifiant d'une règle système. Énumération fermée : un identifiant inconnu est refusé.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum SystemRuleId {
    #[serde(rename = "sys.logs.library")]
    LogsLibrary,
    #[serde(rename = "sys.logs.diagnostic-reports")]
    LogsDiagnosticReports,
    #[serde(rename = "sys.logs.rotated")]
    LogsRotated,
}

impl SystemRuleId {
    pub const ALL: [SystemRuleId; 3] =
        [SystemRuleId::LogsLibrary, SystemRuleId::LogsDiagnosticReports, SystemRuleId::LogsRotated];

    pub fn as_str(self) -> &'static str {
        match self {
            SystemRuleId::LogsLibrary => "sys.logs.library",
            SystemRuleId::LogsDiagnosticReports => "sys.logs.diagnostic-reports",
            SystemRuleId::LogsRotated => "sys.logs.rotated",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|r| r.as_str() == s)
    }

    /// La règle réelle, avec sa racine système.
    pub fn rule(self) -> SystemRule {
        let root = match self {
            SystemRuleId::LogsLibrary => "/Library/Logs",
            SystemRuleId::LogsDiagnosticReports => "/Library/Logs/DiagnosticReports",
            // `/var` est un lien vers `/private/var` : on vise le chemin réel.
            SystemRuleId::LogsRotated => "/private/var/log",
        };
        SystemRule::at(self, PathBuf::from(root), is_system_id)
    }
}

/// Comptes et groupes système (macOS réserve les identifiants sous 500).
pub fn is_system_id(id: u32) -> bool {
    id < 500
}

const DAY: u64 = 86_400;

/// Une règle système : racine, ancienneté minimale, filtre de noms, propriétaires admis.
#[derive(Debug, Clone)]
pub struct SystemRule {
    pub id: SystemRuleId,
    pub root: PathBuf,
    pub min_age: Duration,
    /// Dossiers de premier niveau exclus (ex. `DiagnosticReports`, couvert par sa propre règle).
    pub exclude_top: &'static [&'static str],
    /// Seulement des archives de rotation déjà fermées (`*.gz`, `*.bz2`, `*.xz`, `*.N`).
    pub archives_only: bool,
    /// Propriétaires admis (fichiers et dossiers). Système uniquement pour les règles réelles.
    pub owner_ok: fn(u32) -> bool,
}

impl SystemRule {
    /// Paramètres de la règle `id`, appliqués à `root`. Les règles réelles passent par
    /// [`SystemRuleId::rule`] ; une autre racine ne sert qu'aux tests sans privilèges.
    pub fn at(id: SystemRuleId, root: PathBuf, owner_ok: fn(u32) -> bool) -> Self {
        let (min_age, exclude_top, archives_only): (u64, &'static [&'static str], bool) = match id {
            SystemRuleId::LogsLibrary => (30 * DAY, &["DiagnosticReports"], false),
            SystemRuleId::LogsDiagnosticReports => (30 * DAY, &[], false),
            // Une archive est fermée par construction ; un jour de marge contre une rotation en cours.
            SystemRuleId::LogsRotated => (DAY, &[], true),
        };
        SystemRule { id, root, min_age: Duration::from_secs(min_age), exclude_top, archives_only, owner_ok }
    }
}

/// Bornes d'une opération.
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub max_items: usize,
    pub max_duration: Duration,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { max_items: 10_000, max_duration: Duration::from_secs(60) }
    }
}

/// Un élément listé. `rel_path` sert à l'affichage ; seule l'identité fait autorité.
#[derive(Debug, Clone, serde::Serialize)]
pub struct SystemItem {
    pub rel_path: String,
    pub size_bytes: u64,
    pub modified: i64,
    pub identity: FileIdentity,
}

#[derive(Debug, Default, serde::Serialize)]
pub struct Listing {
    pub items: Vec<SystemItem>,
    /// Éléments écartés et pourquoi (lien, autre volume, dossier non sûr, verrouillé…).
    pub skipped: Vec<(String, &'static str)>,
    /// Vrai si la limite de nombre ou de durée a été atteinte.
    pub truncated: bool,
}

#[derive(Debug, Default, serde::Serialize)]
pub struct RemoveReport {
    pub removed: usize,
    pub freed_bytes: u64,
    /// Éléments demandés mais non supprimés, et pourquoi.
    pub refused: Vec<(String, &'static str)>,
    /// Identités demandées introuvables dans la règle (jamais supprimées).
    pub not_found: usize,
    pub truncated: bool,
}

/// Descripteur possédé, fermé à la destruction.
struct Fd(libc::c_int);

impl Drop for Fd {
    fn drop(&mut self) {
        unsafe { libc::close(self.0) };
    }
}

const DIR_FLAGS: libc::c_int = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;
const LOCKED: u32 = libc::UF_IMMUTABLE | libc::SF_IMMUTABLE | libc::UF_APPEND | libc::SF_APPEND;
const MAX_DEPTH: usize = 32;

fn stat_at(dir: &Fd, name: &CStr) -> Option<libc::stat> {
    let mut st: libc::stat = unsafe { std::mem::zeroed() };
    let r = unsafe { libc::fstatat(dir.0, name.as_ptr(), &mut st, libc::AT_SYMLINK_NOFOLLOW) };
    (r == 0).then_some(st)
}

fn kind(st: &libc::stat) -> libc::mode_t {
    st.st_mode & libc::S_IFMT
}

fn identity(st: &libc::stat) -> FileIdentity {
    // Mêmes conventions que `FileIdentity::of_path` (dev_t signé étendu).
    FileIdentity { device: st.st_dev as i64 as u64, inode: st.st_ino }
}

/// Noms des entrées d'un dossier ouvert (hors `.` et `..`), lus d'un coup.
fn entries(dir: &Fd) -> Vec<CString> {
    let dup = unsafe { libc::dup(dir.0) };
    if dup < 0 {
        return Vec::new();
    }
    let d = unsafe { libc::fdopendir(dup) };
    if d.is_null() {
        unsafe { libc::close(dup) };
        return Vec::new();
    }
    let mut out = Vec::new();
    loop {
        let e = unsafe { libc::readdir(d) };
        if e.is_null() {
            break;
        }
        let name = unsafe { CStr::from_ptr((*e).d_name.as_ptr()) };
        if name.to_bytes() != b"." && name.to_bytes() != b".." {
            out.push(name.to_owned());
        }
    }
    unsafe { libc::closedir(d) };
    out
}

impl SystemRule {
    /// Un dossier est sûr s'il appartient à un propriétaire admis, n'est pas inscriptible par
    /// tous, et n'est inscriptible par son groupe que si ce groupe est un groupe système.
    fn dir_trusted(&self, st: &libc::stat) -> bool {
        let mode = st.st_mode as u32;
        (self.owner_ok)(st.st_uid)
            && mode & libc::S_IWOTH as u32 == 0
            && (mode & libc::S_IWGRP as u32 == 0 || is_system_id(st.st_gid))
    }

    /// Vrai si le nom désigne une archive de rotation fermée.
    fn is_archive(name: &str) -> bool {
        let lower = name.to_ascii_lowercase();
        if [".gz", ".bz2", ".xz", ".zst"].iter().any(|e| lower.ends_with(e)) {
            return true;
        }
        match lower.rsplit_once('.') {
            Some((stem, ext)) => !stem.is_empty() && !ext.is_empty() && ext.bytes().all(|b| b.is_ascii_digit()),
            None => false,
        }
    }

    /// Le fichier satisfait-il la règle maintenant ? Sinon, pourquoi.
    fn eligible(&self, name: &str, st: &libc::stat, now: i64) -> Result<(), &'static str> {
        if !(self.owner_ok)(st.st_uid) {
            return Err("propriétaire non système");
        }
        if st.st_flags & LOCKED != 0 {
            return Err("verrouillé");
        }
        if st.st_nlink > 1 {
            return Err("liens multiples");
        }
        if self.archives_only && !Self::is_archive(name) {
            return Err("pas une archive");
        }
        if now - st.st_mtime < self.min_age.as_secs() as i64 {
            return Err("trop récent");
        }
        Ok(())
    }

    /// Parcours relatif aux descripteurs. `visit(dossier, nom, chemin relatif, stat)` est appelé
    /// pour chaque fichier ordinaire ; `skip` pour chaque élément écarté. Renvoie vrai si arrêté
    /// par les limites (`stop` renvoyé par `visit`).
    fn walk(
        &self,
        limits: Limits,
        visit: &mut dyn FnMut(&Fd, &CStr, &str, &libc::stat) -> bool,
        skip: &mut dyn FnMut(String, &'static str),
    ) -> Result<bool, String> {
        let root_c = CString::new(self.root.as_os_str().as_encoded_bytes()).map_err(|e| e.to_string())?;
        if !self.root.is_absolute() || !matches!(crate::safety::symlink_in_path(&self.root), Ok(false)) {
            return Err(format!("racine invalide : {}", self.root.display()));
        }
        let root = Fd(unsafe { libc::open(root_c.as_ptr(), DIR_FLAGS) });
        if root.0 < 0 {
            return Err(format!("racine illisible : {}", std::io::Error::last_os_error()));
        }
        let mut root_st: libc::stat = unsafe { std::mem::zeroed() };
        if unsafe { libc::fstat(root.0, &mut root_st) } != 0 || !self.dir_trusted(&root_st) {
            return Err("racine non sûre".into());
        }
        let device = root_st.st_dev;
        let started = Instant::now();
        let mut stack: Vec<(Fd, String, usize)> = vec![(root, String::new(), 0)];

        while let Some((dir, rel, depth)) = stack.pop() {
            for name in entries(&dir) {
                if started.elapsed() > limits.max_duration {
                    return Ok(true);
                }
                let shown = name.to_string_lossy();
                let child_rel = if rel.is_empty() { shown.to_string() } else { format!("{rel}/{shown}") };
                let Some(st) = stat_at(&dir, &name) else { continue };
                match kind(&st) {
                    libc::S_IFREG => {
                        if visit(&dir, &name, &child_rel, &st) {
                            return Ok(true);
                        }
                    }
                    libc::S_IFDIR => {
                        if depth == 0 && self.exclude_top.contains(&shown.as_ref()) {
                            continue;
                        }
                        if st.st_dev != device {
                            skip(child_rel, "autre volume");
                            continue;
                        }
                        if !self.dir_trusted(&st) {
                            skip(child_rel, "dossier non sûr");
                            continue;
                        }
                        if depth + 1 >= MAX_DEPTH {
                            skip(child_rel, "trop profond");
                            continue;
                        }
                        let fd = Fd(unsafe { libc::openat(dir.0, name.as_ptr(), DIR_FLAGS) });
                        if fd.0 < 0 {
                            continue;
                        }
                        // Le dossier ouvert est-il bien celui qu'on a examiné ?
                        let mut opened: libc::stat = unsafe { std::mem::zeroed() };
                        if unsafe { libc::fstat(fd.0, &mut opened) } != 0
                            || opened.st_dev != st.st_dev
                            || opened.st_ino != st.st_ino
                        {
                            skip(child_rel, "modifié pendant la lecture");
                            continue;
                        }
                        stack.push((fd, child_rel, depth + 1));
                    }
                    libc::S_IFLNK => skip(child_rel, "lien"),
                    _ => {}
                }
            }
        }
        Ok(false)
    }
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// Liste les éléments de la règle. Ne modifie rien.
pub fn list(rule: &SystemRule, limits: Limits) -> Result<Listing, String> {
    let mut out = Listing::default();
    let now = now();
    let mut items = Vec::new();
    let mut skipped = Vec::new();
    let mut walk_skipped = Vec::new();
    let truncated = rule.walk(
        limits,
        &mut |_, name, rel, st| {
            match rule.eligible(&name.to_string_lossy(), st, now) {
                Ok(()) => items.push(SystemItem {
                    rel_path: rel.to_string(),
                    size_bytes: st.st_blocks as u64 * 512,
                    modified: st.st_mtime,
                    identity: identity(st),
                }),
                Err("trop récent" | "pas une archive") => {}
                Err(why) => skipped.push((rel.to_string(), why)),
            }
            items.len() >= limits.max_items
        },
        &mut |rel, why| walk_skipped.push((rel, why)),
    )?;
    skipped.extend(walk_skipped);
    out.items = items;
    out.skipped = skipped;
    out.truncated = truncated;
    Ok(out)
}

/// Supprime **définitivement** les éléments de la règle dont l'identité figure dans `wanted`.
/// La règle est réénumérée : un élément n'est supprimé que s'il la satisfait encore et que son
/// identité, relue juste avant `unlinkat` dans le même dossier ouvert, n'a pas changé.
pub fn remove(rule: &SystemRule, wanted: &[FileIdentity], limits: Limits) -> Result<RemoveReport, String> {
    let wanted: HashSet<(u64, u64)> = wanted.iter().map(|i| (i.device, i.inode)).collect();
    let mut seen: HashSet<(u64, u64)> = HashSet::new();
    let mut report = RemoveReport::default();
    let now = now();
    let mut refused = Vec::new();
    let truncated = rule.walk(
        limits,
        &mut |dir, name, rel, st| {
            let id = identity(st);
            if !wanted.contains(&(id.device, id.inode)) {
                return false;
            }
            seen.insert((id.device, id.inode));
            if let Err(why) = rule.eligible(&name.to_string_lossy(), st, now) {
                refused.push((rel.to_string(), why));
                return false;
            }
            // Dernière vérification, dans le même dossier ouvert, juste avant de délier.
            match stat_at(dir, name) {
                Some(again) if kind(&again) == libc::S_IFREG && identity(&again) == id => {}
                _ => {
                    refused.push((rel.to_string(), "modifié depuis la liste"));
                    return false;
                }
            }
            if unsafe { libc::unlinkat(dir.0, name.as_ptr(), 0) } == 0 {
                report.removed += 1;
                report.freed_bytes += st.st_blocks as u64 * 512;
            } else {
                let why = match std::io::Error::last_os_error().raw_os_error() {
                    Some(libc::EPERM) => "protégé par le système",
                    Some(libc::EACCES) => "accès refusé",
                    _ => "échec de suppression",
                };
                refused.push((rel.to_string(), why));
            }
            report.removed >= limits.max_items
        },
        &mut |_, _| {},
    )?;
    report.refused = refused;
    report.not_found = wanted.len().saturating_sub(seen.len());
    report.truncated = truncated;
    Ok(report)
}

/// Pour les tests : vrai si `path` existe encore (sans suivre de lien).
pub fn exists(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}
