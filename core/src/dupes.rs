//! Doublons du dossier personnel (module « Doublons »).
//!
//! Recherche en trois passes, chacune ne lisant que ce qui reste ambigu :
//! 1. **taille** identique (aucune lecture) ;
//! 2. **empreinte de bord** : SHA-256 des 64 Kio de tête et de queue ;
//! 3. **empreinte complète** (SHA-256 du contenu) pour les candidats restants.
//!
//! Même périmètre que « Gros fichiers » (dossier personnel hors `~/Library`, ni caché ni paquet).
//! Un fichier à liens physiques multiples n'est jamais proposé : en retirer un chemin ne libère
//! rien, et ce n'est pas une copie.
//!
//! Au retrait ([`evaluate_group`]), le moteur ne se fie pas à l'analyse : il exige une copie
//! conservée présente et inchangée, puis compare **octet par octet** chaque fichier à retirer avec
//! elle. Une sélection forgée ou périmée ne peut donc pas faire disparaître la dernière copie
//! d'un contenu.

use crate::large;
use crate::model::FileIdentity;
use crate::safety::{Decision, Refusal, SafetyContext};
use crate::walk::{self, Budget, Control, FoundFile, WalkOptions};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

/// Taille minimale par défaut d'un fichier examiné : 1 Mio.
pub const DEFAULT_MIN_BYTES: u64 = 1024 * 1024;
/// Budget par défaut du parcours (la comparaison des contenus, elle, reste annulable).
pub const DEFAULT_BUDGET: Duration = Duration::from_secs(180);
/// Taille des bords lus à la deuxième passe.
const EDGE: u64 = 64 * 1024;
const CHUNK: usize = 1024 * 1024;

/// Un fichier d'un groupe de doublons.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DupFile {
    pub path: PathBuf,
    /// Octets alloués sur disque.
    pub size_bytes: u64,
    /// Dernière modification, secondes depuis l'époque Unix.
    pub modified: i64,
    pub identity: FileIdentity,
}

/// Des fichiers au contenu identique.
#[derive(Debug, Clone, serde::Serialize)]
pub struct DupGroup {
    /// Taille logique du contenu commun.
    pub length: u64,
    /// Du plus ancien au plus récent.
    pub files: Vec<DupFile>,
}

impl DupGroup {
    /// Espace libéré en ne gardant qu'un exemplaire (estimation : un clone APFS partage déjà ses
    /// blocs et ne libérerait rien).
    pub fn reclaimable(&self) -> u64 {
        let max = self.files.iter().map(|f| f.size_bytes).max().unwrap_or(0);
        self.files.iter().map(|f| f.size_bytes).sum::<u64>() - max
    }
}

#[derive(Debug, Default)]
pub struct DupOutcome {
    /// Triés par espace récupérable décroissant.
    pub groups: Vec<DupGroup>,
    pub warnings: Vec<String>,
    /// Faux si le parcours a été interrompu (échéance, blocage) : groupes possiblement incomplets.
    pub complete: bool,
    pub cancelled: bool,
}

/// Recherche les doublons d'au moins `min_bytes` octets alloués sous `root` (racine validée par
/// l'appelant avec [`large::validate_root`]).
pub fn find_duplicates(root: &Path, min_bytes: u64, budget: Budget, control: &Arc<Control>) -> DupOutcome {
    let mut outcome = DupOutcome::default();
    let options = WalkOptions {
        skip_hidden: true,
        skip_packages: true,
        exclude: vec![],
        collect_min: Some(min_bytes.max(1)),
        skip_projects: true,
    };
    let walked = walk::walk_paths(&[root.to_path_buf()], budget, control, options);
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }
    outcome.complete = walked.sizes.first().is_some_and(|m| m.complete);
    if !outcome.complete {
        outcome.warnings.push(format!("parcours interrompu (budget) : recherche partielle sous {}", root.display()));
    }

    // 1. Même taille logique. Liens physiques et fichiers hors périmètre écartés.
    let mut by_len: HashMap<u64, Vec<FoundFile>> = HashMap::new();
    for f in walked.found {
        if f.nlink == 1 && f.len > 0 && large::is_eligible(&f.path, root) {
            by_len.entry(f.len).or_default().push(f);
        }
    }
    let candidates: Vec<Vec<FoundFile>> = by_len.into_values().filter(|g| g.len() > 1).collect();

    // 2. Empreinte des bords ; 3. empreinte complète des fichiers plus grands que les deux bords.
    let edged = refine(candidates, control, &mut outcome.warnings, edge_digest);
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }
    let full = refine(edged, control, &mut outcome.warnings, |p, len| full_digest(p, len, control));
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }

    for mut group in full {
        group.sort_by(|a, b| a.modified.cmp(&b.modified).then(a.path.cmp(&b.path)));
        let length = group[0].len;
        let files = group
            .into_iter()
            .map(|f| DupFile {
                path: f.path,
                size_bytes: f.bytes,
                modified: f.modified,
                identity: FileIdentity { device: f.dev, inode: f.ino },
            })
            .collect();
        outcome.groups.push(DupGroup { length, files });
    }
    outcome.groups.sort_by_key(|g| std::cmp::Reverse(g.reclaimable()));
    outcome
}

/// Re-partitionne chaque groupe selon une empreinte calculée en parallèle. Les fichiers
/// illisibles ou modifiés en cours de route sortent du groupe.
fn refine(
    groups: Vec<Vec<FoundFile>>,
    control: &Arc<Control>,
    warnings: &mut Vec<String>,
    digest: impl Fn(&Path, u64) -> std::io::Result<[u8; 32]> + Sync,
) -> Vec<Vec<FoundFile>> {
    let jobs: Vec<(usize, usize)> = groups
        .iter()
        .enumerate()
        .flat_map(|(g, files)| (0..files.len()).map(move |i| (g, i)))
        .collect();
    let results: Vec<std::sync::Mutex<Option<std::io::Result<[u8; 32]>>>> =
        jobs.iter().map(|_| std::sync::Mutex::new(None)).collect();
    let next = AtomicUsize::new(0);
    let workers = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, 8);

    std::thread::scope(|scope| {
        for _ in 0..workers.min(jobs.len().max(1)) {
            scope.spawn(|| {
                walk::disable_materialization();
                loop {
                    let k = next.fetch_add(1, Ordering::Relaxed);
                    if k >= jobs.len() || control.is_cancelled() {
                        return;
                    }
                    let (g, i) = jobs[k];
                    let f = &groups[g][i];
                    *results[k].lock().unwrap() = Some(digest(&f.path, f.len));
                    control.add_progress(1, 0);
                }
            });
        }
    });

    let mut digests: HashMap<(usize, [u8; 32]), Vec<FoundFile>> = HashMap::new();
    let mut groups: Vec<Vec<Option<FoundFile>>> = groups.into_iter().map(|g| g.into_iter().map(Some).collect()).collect();
    for (k, (g, i)) in jobs.iter().enumerate() {
        let file = groups[*g][*i].take().expect("chaque fichier n'est traité qu'une fois");
        match results[k].lock().unwrap().take() {
            Some(Ok(d)) => digests.entry((*g, d)).or_default().push(file),
            Some(Err(e)) => warnings.push(format!("ignoré (illisible) {} : {e}", file.path.display())),
            None => {} // annulé
        }
    }
    digests.into_values().filter(|g| g.len() > 1).collect()
}

/// Ouvre un fichier ordinaire sans suivre de lien et vérifie qu'il a encore la taille attendue.
fn open_checked(path: &Path, len: u64) -> std::io::Result<File> {
    let file = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    let md = file.metadata()?;
    if !md.is_file() || md.len() != len {
        return Err(std::io::Error::other("modifié pendant l'analyse"));
    }
    Ok(file)
}

/// SHA-256 de la taille, des 64 Kio de tête et des 64 Kio de queue (le fichier entier s'il est
/// plus petit que les deux bords réunis).
fn edge_digest(path: &Path, len: u64) -> std::io::Result<[u8; 32]> {
    let mut file = open_checked(path, len)?;
    let mut h = Sha256::new();
    h.update(len.to_le_bytes());
    let mut buf = vec![0u8; EDGE as usize];
    if len <= 2 * EDGE {
        let mut all = Vec::with_capacity(len as usize);
        file.read_to_end(&mut all)?;
        h.update(&all);
    } else {
        file.read_exact(&mut buf)?;
        h.update(&buf);
        file.seek(SeekFrom::Start(len - EDGE))?;
        file.read_exact(&mut buf)?;
        h.update(&buf);
    }
    Ok(h.finalize().into())
}

/// SHA-256 du contenu complet, par blocs ; abandonne dès que la tâche est annulée.
fn full_digest(path: &Path, len: u64, control: &Arc<Control>) -> std::io::Result<[u8; 32]> {
    let mut file = open_checked(path, len)?;
    let mut h = Sha256::new();
    h.update(len.to_le_bytes());
    let mut buf = vec![0u8; CHUNK];
    loop {
        if control.is_cancelled() {
            return Err(std::io::Error::other("annulé"));
        }
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
        control.add_progress(0, n as u64);
    }
    Ok(h.finalize().into())
}

/// Un fichier désigné par l'app pour la validation.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub path: PathBuf,
    pub identity: FileIdentity,
}

/// Vrai si les deux fichiers ont exactement le même contenu (comparaison octet par octet).
fn same_content(a: &Path, b: &Path) -> std::io::Result<bool> {
    let open = |p: &Path| std::fs::OpenOptions::new().read(true).custom_flags(libc::O_NOFOLLOW).open(p);
    let (mut fa, mut fb) = (open(a)?, open(b)?);
    let (ma, mb) = (fa.metadata()?, fb.metadata()?);
    if !ma.is_file() || !mb.is_file() || ma.len() != mb.len() {
        return Ok(false);
    }
    let (mut ba, mut bb) = (vec![0u8; CHUNK], vec![0u8; CHUNK]);
    loop {
        let n = fa.read(&mut ba)?;
        if n == 0 {
            return Ok(true);
        }
        fb.read_exact(&mut bb[..n])?;
        if ba[..n] != bb[..n] {
            return Ok(false);
        }
    }
}

/// Valide le retrait des fichiers `remove` d'un groupe dont `keep` est l'exemplaire conservé.
/// Une décision par élément de `remove`, dans l'ordre. Règles, toutes appliquées par le moteur :
///
/// - `keep` doit être éligible sous `root`, présent, fichier ordinaire, d'identité inchangée,
///   et absent de `remove` — sinon **tout** le groupe est refusé (`NoKeptCopy`) ;
/// - un élément de même identité que `keep` (même fichier) est refusé (`NoKeptCopy`) ;
/// - chaque élément doit avoir **exactement** le contenu de `keep` maintenant (`NotDuplicate`) ;
/// - puis les gardes de [`large::evaluate`] (éligibilité, protections, identité, liens).
pub fn evaluate_group(
    ctx: &SafetyContext,
    root: &Path,
    keep: &Candidate,
    remove: &[Candidate],
) -> Vec<Decision> {
    let keep_norm = crate::path_util::lexical_normalize(&keep.path);
    let keep_ok = large::is_eligible(&keep.path, root)
        && std::fs::symlink_metadata(&keep.path).is_ok_and(|m| m.file_type().is_file())
        && FileIdentity::of_path(&keep.path).is_ok_and(|id| id == keep.identity)
        && !remove
            .iter()
            .any(|r| crate::path_util::lexical_normalize(&r.path) == keep_norm);
    if !keep_ok {
        return remove
            .iter()
            .map(|r| Decision::Refused(Refusal::NoKeptCopy(r.path.clone())))
            .collect();
    }

    remove
        .iter()
        .map(|r| {
            let same_file = std::fs::symlink_metadata(&r.path)
                .is_ok_and(|m| m.dev() == keep.identity.device && m.ino() == keep.identity.inode);
            if same_file || r.identity == keep.identity {
                return Decision::Refused(Refusal::NoKeptCopy(r.path.clone()));
            }
            let decision = large::evaluate(ctx, &r.path, root, r.identity);
            if !decision.is_allowed() {
                return decision;
            }
            match same_content(&r.path, &keep.path) {
                Ok(true) => Decision::Allowed,
                Ok(false) | Err(_) => Decision::Refused(Refusal::NotDuplicate(r.path.clone())),
            }
        })
        .collect()
}

/// Un groupe soumis à validation : l'exemplaire conservé et ceux à retirer.
#[derive(Debug, Clone)]
pub struct PlanGroup {
    pub keep: Candidate,
    pub remove: Vec<Candidate>,
}

/// Valide plusieurs groupes **ensemble** : un fichier conservé dans un groupe ne peut être retiré
/// dans aucun autre (sinon deux groupes croisés feraient disparaître toutes les copies).
/// Décisions aplaties, dans l'ordre des groupes puis des éléments.
pub fn evaluate_groups(ctx: &SafetyContext, root: &Path, groups: &[PlanGroup]) -> Vec<(PathBuf, Decision)> {
    let kept_paths: Vec<PathBuf> = groups
        .iter()
        .map(|g| crate::path_util::lexical_normalize(&g.keep.path))
        .collect();
    let kept_ids: Vec<FileIdentity> = groups.iter().map(|g| g.keep.identity).collect();

    let mut out = Vec::new();
    for g in groups {
        let decisions = evaluate_group(ctx, root, &g.keep, &g.remove);
        for (r, d) in g.remove.iter().zip(decisions) {
            let kept_elsewhere = kept_paths.contains(&crate::path_util::lexical_normalize(&r.path))
                || kept_ids.contains(&r.identity);
            let d = if kept_elsewhere { Decision::Refused(Refusal::NoKeptCopy(r.path.clone())) } else { d };
            out.push((r.path.clone(), d));
        }
    }
    out
}
