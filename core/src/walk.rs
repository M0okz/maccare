//! Mesure parallèle de l'espace disque occupé par des arborescences.
//!
//! C'est le chemin chaud du moteur : chaque scan et chaque niveau d'« Espace disque » y passent.
//! Principes, par ordre d'importance :
//!
//! - **Ne jamais figer.** Un montage réseau ou un dossier servi par un *File Provider* peut
//!   bloquer un appel noyau indéfiniment. Les workers sont détachés ; l'appelant attend au plus
//!   jusqu'à l'échéance, et abandonne plus tôt si plus rien n'avance (`stall`). Une racine non
//!   terminée est rendue avec sa taille partielle et `complete = false`.
//! - **Ne rien provoquer.** On ne matérialise jamais un fichier iCloud « dataless » (politique
//!   d'E/S du thread), on ne descend pas dans un dossier dataless, on ne suit aucun lien
//!   symbolique et on ne franchit pas de point de montage.
//! - **Compter ce qui sera libéré.** Taille *allouée* (blocs sur disque, comme `du`), et un
//!   fichier à liens physiques multiples n'est compté qu'une fois.
//! - **Aller vite.** Pool borné de workers partageant une file de dossiers ; sur macOS,
//!   `getattrlistbulk` lit nom, type, identité et taille de tout un dossier en quelques appels.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

/// Délai sans aucune progression au-delà duquel on considère que le travail restant est bloqué.
pub const STALL_TIMEOUT: Duration = Duration::from_secs(4);

/// Bornes de temps d'une mesure.
#[derive(Debug, Clone, Copy)]
pub struct Budget {
    /// Durée maximale totale.
    pub total: Duration,
    /// Abandon anticipé si aucune entrée n'a été lue pendant cette durée.
    pub stall: Duration,
}

impl Budget {
    pub fn new(total: Duration) -> Self {
        Budget { total, stall: STALL_TIMEOUT.min(total) }
    }
}

/// Contrôle partagé d'une tâche longue : annulation demandée par l'appelant et compteurs de
/// progression lisibles depuis un autre thread pendant le travail. Un même contrôle peut couvrir
/// plusieurs mesures successives (un scan entier) : les compteurs s'additionnent.
#[derive(Debug, Default)]
pub struct Control {
    cancelled: AtomicBool,
    entries: AtomicU64,
    bytes: AtomicU64,
}

impl Control {
    pub fn new() -> Arc<Self> {
        Arc::new(Control::default())
    }

    /// Demande l'arrêt. Effet en moins de [`CANCEL_LATENCY`] côté appelant ; les workers bloqués
    /// dans le noyau se dénouent d'eux-mêmes, détachés.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// Entrées de dossier lues jusqu'ici.
    pub fn entries(&self) -> u64 {
        self.entries.load(Ordering::Relaxed)
    }

    /// Octets alloués comptés jusqu'ici.
    pub fn bytes(&self) -> u64 {
        self.bytes.load(Ordering::Relaxed)
    }

    /// Ajoute de la progression hors parcours (ex. contenus lus pour comparer des fichiers).
    pub fn add_progress(&self, entries: u64, bytes: u64) {
        self.entries.fetch_add(entries, Ordering::Relaxed);
        self.bytes.fetch_add(bytes, Ordering::Relaxed);
    }
}

/// Interdit au thread appelant de déclencher le téléchargement d'un fichier iCloud « dataless » :
/// une lecture échoue au lieu d'attendre le réseau. À appeler sur tout thread qui lit des contenus.
pub fn disable_materialization() {
    platform::disable_materialization();
}

/// Délai maximal entre une demande d'annulation et le retour de l'appelant.
pub const CANCEL_LATENCY: Duration = Duration::from_millis(50);

/// Taille mesurée d'une racine.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Measured {
    /// Octets alloués sur disque (borne inférieure si `complete` est faux).
    pub bytes: u64,
    /// Faux si la mesure a été interrompue (échéance, blocage ou annulation).
    pub complete: bool,
}

/// Options de parcours. Par défaut : tout l'arbre, rien de collecté (simple mesure).
#[derive(Debug, Clone, Default)]
pub struct WalkOptions {
    /// Ignorer les entrées cachées (nom commençant par `.`) : ni descente, ni comptage.
    pub skip_hidden: bool,
    /// Ne pas descendre dans les paquets macOS (`.app`, bibliothèques Photos…) : leur contenu
    /// n'a de sens que pour l'application qui les gère.
    pub skip_packages: bool,
    /// Arbres ignorés entièrement (comparaison par composant).
    pub exclude: Vec<PathBuf>,
    /// Si présent, collecte chaque fichier d'au moins ce nombre d'octets alloués.
    pub collect_min: Option<u64>,
    /// Ignorer les projets de code et leurs artefacts : dossiers contenant `.git` ou
    /// `CACHEDIR.TAG`, et dossiers de dépendances (`node_modules`…). Leurs fichiers n'ont de sens
    /// qu'ensemble et se gèrent avec leurs outils (ou le module Dev junk).
    pub skip_projects: bool,
}

/// Dossiers de dépendances ou d'artefacts régénérés par les outils de développement.
const PROJECT_DIR_NAMES: &[&str] =
    &["node_modules", "bower_components", "Pods", "DerivedData", "__pycache__", "venv", "site-packages"];

/// Vrai si `dir` est un projet de code ou un dossier d'artefacts (voir [`WalkOptions::skip_projects`]).
fn is_project_dir(dir: &Path) -> bool {
    dir.file_name()
        .and_then(|n| n.to_str())
        .is_some_and(|n| PROJECT_DIR_NAMES.contains(&n))
        || dir.ends_with("pkg/mod") // cache de modules Go
        || std::fs::symlink_metadata(dir.join(".git")).is_ok()
        || std::fs::symlink_metadata(dir.join("CACHEDIR.TAG")).is_ok()
}

/// Extensions de paquets macOS : dossiers présentés comme un seul document par le Finder.
const PACKAGE_EXTENSIONS: &[&str] = &[
    "app", "appex", "bundle", "framework", "plugin", "kext", "xpc", "photoslibrary",
    "photolibrary", "aplibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
    "logicx", "band", "xcarchive", "sparsebundle", "pages", "numbers", "key", "rtfd",
    "playground", "mlpackage", "lrlibrary", "lrdata",
];

/// Vrai si ce nom désigne un paquet macOS (selon son extension).
pub fn is_package_name(name: &std::ffi::OsStr) -> bool {
    Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| PACKAGE_EXTENSIONS.iter().any(|p| p.eq_ignore_ascii_case(e)))
        .unwrap_or(false)
}

impl WalkOptions {
    /// Vrai si l'entrée `name` (chemin `path`) doit être entièrement ignorée.
    fn skips(&self, name: &std::ffi::OsStr, path: &Path, is_dir: bool) -> bool {
        (self.skip_hidden && name.as_encoded_bytes().first() == Some(&b'.'))
            || (is_dir && self.skip_packages && is_package_name(name))
            || (is_dir && self.exclude.iter().any(|x| crate::path_util::is_within(path, x)))
    }
}

/// Un fichier collecté pendant le parcours (voir [`WalkOptions::collect_min`]).
#[derive(Debug, Clone)]
pub struct FoundFile {
    pub path: PathBuf,
    /// Octets alloués sur disque.
    pub bytes: u64,
    /// Taille logique (longueur du contenu).
    pub len: u64,
    /// Date de dernière modification, en secondes depuis l'époque Unix.
    pub modified: i64,
    pub dev: u64,
    pub ino: u64,
    /// Nombre de liens physiques.
    pub nlink: u64,
}

/// Résultat d'un parcours : tailles par racine, et fichiers collectés le cas échéant.
#[derive(Debug, Default)]
pub struct WalkResult {
    pub sizes: Vec<Measured>,
    pub found: Vec<FoundFile>,
}

/// Mesure plusieurs racines **ensemble**, sur un même pool de workers. Le résultat est dans
/// l'ordre des racines fournies. Une racine absente ou illisible vaut 0 (mesure complète).
pub fn measure_paths(roots: &[PathBuf], budget: Budget) -> Vec<Measured> {
    measure_paths_with(roots, budget, &Control::new())
}

/// [`measure_paths`] sous un [`Control`] : annulable et observable pendant la mesure.
pub fn measure_paths_with(roots: &[PathBuf], budget: Budget, control: &Arc<Control>) -> Vec<Measured> {
    walk_paths(roots, budget, control, WalkOptions::default()).sizes
}

/// Parcours général : mesure les racines selon `options`, et collecte les gros fichiers si demandé.
pub fn walk_paths(roots: &[PathBuf], budget: Budget, control: &Arc<Control>, options: WalkOptions) -> WalkResult {
    let shared = Arc::new(Shared::new(roots.len(), Arc::clone(control), options));
    let mut initial = Vec::new();

    for (i, root) in roots.iter().enumerate() {
        if control.is_cancelled() {
            break;
        }
        let Ok(md) = std::fs::symlink_metadata(root) else { continue };
        let ft = md.file_type();
        if ft.is_file() {
            let bytes = md.blocks() * 512;
            if shared.add_file(i, md.dev(), md.ino(), md.nlink(), bytes) {
                shared.collect(FoundFile {
                    path: root.clone(),
                    bytes,
                    len: md.len(),
                    modified: md.mtime(),
                    dev: md.dev(),
                    ino: md.ino(),
                    nlink: md.nlink(),
                });
            }
        } else if ft.is_dir() && !is_dataless(st_flags(&md)) {
            initial.push(Task { root: i, path: root.clone(), device: md.dev() });
        }
        // Lien symbolique, dossier dataless ou objet spécial : 0, sans descendre.
    }

    if !initial.is_empty() && !control.is_cancelled() {
        let workers = worker_count().min(initial.len().max(1) * 4);
        {
            let mut q = shared.queue.lock().unwrap();
            for t in &initial {
                shared.pending[t.root].fetch_add(1, Ordering::SeqCst);
            }
            q.outstanding += initial.len();
            initial.into_iter().for_each(|t| q.push(t));
        }
        for _ in 0..workers {
            let s = Arc::clone(&shared);
            // Détaché à dessein : un worker bloqué dans le noyau ne doit pas retenir l'appelant.
            let _ = std::thread::Builder::new()
                .name("maccare-walk".into())
                .spawn(move || worker(&s));
        }
        wait(&shared, budget);
    }

    let cancelled = control.is_cancelled();
    let sizes = (0..roots.len())
        .map(|i| Measured {
            bytes: shared.totals[i].load(Ordering::SeqCst),
            complete: !cancelled && shared.pending[i].load(Ordering::SeqCst) == 0,
        })
        .collect();
    let found = std::mem::take(&mut *shared.found.lock().unwrap());
    WalkResult { sizes, found }
}

/// Mesure une seule racine. Raccourci de [`measure_paths`].
pub fn measure_path(root: &Path, budget: Budget) -> Measured {
    measure_paths(&[root.to_path_buf()], budget)[0]
}

/// Taille allouée d'un objet **sans descendre** (fichier : ses blocs ; autre : 0).
pub fn allocated_size(md: &std::fs::Metadata) -> u64 {
    if md.file_type().is_file() {
        md.blocks() * 512
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// Pool de workers.
// ---------------------------------------------------------------------------

/// Un dossier à lister, rattaché à la racine dont il compte la taille.
struct Task {
    root: usize,
    path: PathBuf,
    /// Volume de la racine : on ne descend pas dans un dossier d'un autre volume.
    device: u64,
}

/// Travail en attente : **une pile par racine**, servies à tour de rôle.
///
/// Dans une racine, le parcours reste en profondeur d'abord (pile courte). Entre racines, le
/// tourniquet garantit que chacune avance : sous une échéance, une racine immense (`~/Library`)
/// ne peut plus affamer les autres, qui seraient sinon rendues à 0 octet sans avoir été lues.
struct Queue {
    stacks: Vec<Vec<Task>>,
    /// Prochaine racine à servir.
    cursor: usize,
    /// Dossiers en file ou en cours de lecture, toutes racines confondues.
    outstanding: usize,
}

impl Queue {
    fn new(roots: usize) -> Self {
        Queue { stacks: (0..roots).map(|_| Vec::new()).collect(), cursor: 0, outstanding: 0 }
    }

    fn push(&mut self, task: Task) {
        self.stacks[task.root].push(task);
    }

    /// Prochain dossier : le sommet de la pile de la prochaine racine qui a du travail.
    fn pop(&mut self) -> Option<Task> {
        let n = self.stacks.len();
        for i in 0..n {
            let r = (self.cursor + i) % n;
            if let Some(t) = self.stacks[r].pop() {
                self.cursor = (r + 1) % n;
                return Some(t);
            }
        }
        None
    }
}

struct Shared {
    queue: Mutex<Queue>,
    /// Réveille les workers (travail disponible, fin, annulation).
    work: Condvar,
    /// Réveille l'appelant quand tout est terminé.
    finished: Condvar,
    /// Dossiers restant à lire, par racine : 0 = mesure complète.
    pending: Vec<AtomicUsize>,
    totals: Vec<AtomicU64>,
    /// Compteur d'entrées lues, pour détecter un blocage.
    progress: AtomicU64,
    cancel: AtomicBool,
    hardlinks: Mutex<HashSet<(u64, u64)>>,
    control: Arc<Control>,
    options: WalkOptions,
    found: Mutex<Vec<FoundFile>>,
}

impl Shared {
    fn new(roots: usize, control: Arc<Control>, options: WalkOptions) -> Self {
        Shared {
            queue: Mutex::new(Queue::new(roots)),
            work: Condvar::new(),
            finished: Condvar::new(),
            pending: (0..roots).map(|_| AtomicUsize::new(0)).collect(),
            totals: (0..roots).map(|_| AtomicU64::new(0)).collect(),
            progress: AtomicU64::new(0),
            cancel: AtomicBool::new(false),
            hardlinks: Mutex::new(HashSet::new()),
            control,
            options,
            found: Mutex::new(Vec::new()),
        }
    }

    /// Retient le fichier s'il atteint le seuil de collecte.
    fn collect(&self, file: FoundFile) {
        if self.options.collect_min.is_some_and(|min| file.bytes >= min) {
            self.found.lock().unwrap().push(file);
        }
    }

    /// Compte un fichier ; faux s'il est vide ou déjà compté (lien physique).
    fn add_file(&self, root: usize, dev: u64, ino: u64, nlink: u64, bytes: u64) -> bool {
        if bytes == 0 {
            return false;
        }
        // Un fichier à liens multiples n'est compté qu'à sa première rencontre.
        if nlink > 1 && !self.hardlinks.lock().unwrap().insert((dev, ino)) {
            return false;
        }
        self.totals[root].fetch_add(bytes, Ordering::Relaxed);
        self.control.bytes.fetch_add(bytes, Ordering::Relaxed);
        true
    }
}

fn worker_count() -> usize {
    // Les E/S de métadonnées sur SSD profitent d'un parallélisme supérieur au nombre de cœurs,
    // mais au-delà d'une douzaine de threads le gain s'efface devant la contention.
    let cpus = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4);
    cpus.clamp(4, 12)
}

fn worker(shared: &Shared) {
    platform::disable_materialization();
    let mut buf = vec![0u8; 128 * 1024];
    let mut subdirs: Vec<PathBuf> = Vec::new();

    loop {
        let task = {
            let mut q = shared.queue.lock().unwrap();
            loop {
                if shared.cancel.load(Ordering::SeqCst) {
                    return;
                }
                if let Some(t) = q.pop() {
                    break t;
                }
                if q.outstanding == 0 {
                    return;
                }
                q = shared.work.wait(q).unwrap();
            }
        };

        subdirs.clear();
        if !(shared.options.skip_projects && is_project_dir(&task.path)) {
            list_dir(shared, &task, &mut buf, &mut subdirs);
        }

        let mut q = shared.queue.lock().unwrap();
        if !subdirs.is_empty() && !shared.cancel.load(Ordering::SeqCst) {
            // Incrémenter les enfants AVANT de retirer le parent : `pending` ne passe jamais
            // à 0 tant qu'un descendant reste à lire.
            shared.pending[task.root].fetch_add(subdirs.len(), Ordering::SeqCst);
            q.outstanding += subdirs.len();
            for path in subdirs.drain(..) {
                q.push(Task { root: task.root, path, device: task.device });
            }
            shared.work.notify_all();
        }
        shared.pending[task.root].fetch_sub(1, Ordering::SeqCst);
        q.outstanding -= 1;
        if q.outstanding == 0 {
            shared.finished.notify_all();
            shared.work.notify_all();
        }
    }
}

/// Attend la fin du travail, l'échéance, un blocage ou l'annulation. En cas d'abandon, arrête
/// les workers.
fn wait(shared: &Shared, budget: Budget) {
    let start = Instant::now();
    let deadline = start + budget.total;
    let mut last_progress = shared.progress.load(Ordering::Relaxed);
    let mut last_change = start;

    let mut q = shared.queue.lock().unwrap();
    while q.outstanding > 0 {
        let now = Instant::now();
        if now >= deadline || shared.control.is_cancelled() {
            break;
        }
        let p = shared.progress.load(Ordering::Relaxed);
        if p != last_progress {
            last_progress = p;
            last_change = now;
        } else if now.duration_since(last_change) >= budget.stall {
            break;
        }
        let slice = CANCEL_LATENCY.min(deadline - now);
        q = shared.finished.wait_timeout(q, slice).unwrap().0;
    }
    if q.outstanding > 0 {
        shared.cancel.store(true, Ordering::SeqCst);
        shared.work.notify_all();
    }
}

fn is_system_volume_alias(path: &Path) -> bool {
    path == Path::new("/System/Volumes")
}

#[cfg(test)]
mod system_volume_alias_tests {
    use super::*;
    #[test]
    fn logical_system_scan_does_not_enter_duplicate_volume_tree() {
        assert!(is_system_volume_alias(Path::new("/System/Volumes")));
        assert!(!is_system_volume_alias(Path::new("/QA/System/Volumes")));
        assert!(!is_system_volume_alias(Path::new("/System/Volumes/Data")));
        assert!(!is_system_volume_alias(Path::new("/Users")));
    }
}

/// Lit un dossier : additionne ses fichiers, collecte ses sous-dossiers à descendre.
/// Une erreur de lecture (droits, TCC, dossier disparu) compte pour 0 : un scan ne doit jamais
/// échouer à cause d'un dossier.
fn list_dir(shared: &Shared, task: &Task, buf: &mut [u8], subdirs: &mut Vec<PathBuf>) {
    let mut on_entry = |e: Entry<'_>| {
        shared.progress.fetch_add(1, Ordering::Relaxed);
        shared.control.entries.fetch_add(1, Ordering::Relaxed);
        let opts = &shared.options;
        let filtered = opts.skip_hidden || opts.skip_packages || !opts.exclude.is_empty();
        match e.kind {
            Kind::File => {
                if filtered && opts.skips(e.name, &task.path, false) {
                    return;
                }
                if shared.add_file(task.root, e.dev, e.ino, e.nlink, e.alloc) && opts.collect_min.is_some() {
                    shared.collect(FoundFile {
                        path: task.path.join(e.name),
                        bytes: e.alloc,
                        len: e.len,
                        modified: e.modified,
                        dev: e.dev,
                        ino: e.ino,
                        nlink: e.nlink,
                    });
                }
            }
            Kind::Dir if e.dev == task.device && !is_dataless(e.flags) => {
                let child = task.path.join(e.name);
                // APFS peut présenter Data avec le même st_dev que l’arbre logique.
                // Descendre dans /System/Volumes recompterait Users/Applications/Library.
                // Un volume explicitement choisi reste mesurable depuis sa propre racine.
                if is_system_volume_alias(&child) { return; }
                if !(filtered && opts.skips(e.name, &child, true)) {
                    subdirs.push(child);
                }
            }
            _ => {}
        }
    };
    if platform::list_bulk(&task.path, buf, &mut on_entry).is_err() {
        list_std(&task.path, &mut on_entry);
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    File,
    Dir,
    Other,
}

/// Une entrée de dossier, telle que lue par l'un ou l'autre des listeurs.
struct Entry<'a> {
    name: &'a std::ffi::OsStr,
    kind: Kind,
    dev: u64,
    ino: u64,
    nlink: u64,
    flags: u32,
    alloc: u64,
    /// Taille logique du contenu.
    len: u64,
    /// Dernière modification, secondes depuis l'époque Unix.
    modified: i64,
}

/// Listeur portable (repli si `getattrlistbulk` n'est pas pris en charge par le volume).
fn list_std(dir: &Path, on_entry: &mut dyn FnMut(Entry<'_>)) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for entry in rd.flatten() {
        let Ok(md) = entry.metadata() else { continue }; // ne suit pas les liens
        let ft = md.file_type();
        let kind = if ft.is_file() {
            Kind::File
        } else if ft.is_dir() {
            Kind::Dir
        } else {
            Kind::Other
        };
        let name = entry.file_name();
        on_entry(Entry {
            name: &name,
            kind,
            dev: md.dev(),
            ino: md.ino(),
            nlink: md.nlink(),
            flags: st_flags(&md),
            alloc: md.blocks() * 512,
            len: md.len(),
            modified: md.mtime(),
        });
    }
}

/// `SF_DATALESS` : contenu non présent localement (iCloud Drive, File Provider).
const SF_DATALESS: u32 = 0x4000_0000;

fn is_dataless(flags: u32) -> bool {
    flags & SF_DATALESS != 0
}

use std::os::unix::fs::MetadataExt;

#[cfg(target_os = "macos")]
fn st_flags(md: &std::fs::Metadata) -> u32 {
    std::os::macos::fs::MetadataExt::st_flags(md)
}

#[cfg(not(target_os = "macos"))]
fn st_flags(_md: &std::fs::Metadata) -> u32 {
    0
}

// ---------------------------------------------------------------------------
// Spécifique macOS.
// ---------------------------------------------------------------------------

#[cfg(target_os = "macos")]
mod platform {
    use super::{Entry, Kind};
    use std::ffi::{CString, OsStr};
    use std::io;
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;

    extern "C" {
        fn setiopolicy_np(iotype: libc::c_int, scope: libc::c_int, policy: libc::c_int) -> libc::c_int;
    }
    // <sys/resource.h>
    const IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES: libc::c_int = 3;
    const IOPOL_SCOPE_THREAD: libc::c_int = 1;
    const IOPOL_MATERIALIZE_DATALESS_FILES_OFF: libc::c_int = 1;

    /// Interdit à ce thread de déclencher le téléchargement d'un fichier iCloud « dataless » :
    /// l'accès échoue au lieu d'attendre le réseau.
    pub fn disable_materialization() {
        unsafe {
            setiopolicy_np(
                IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
                IOPOL_SCOPE_THREAD,
                IOPOL_MATERIALIZE_DATALESS_FILES_OFF,
            );
        }
    }

    struct Fd(libc::c_int);
    impl Drop for Fd {
        fn drop(&mut self) {
            unsafe { libc::close(self.0) };
        }
    }

    // <sys/attr.h> (absent de la crate libc)
    const ATTR_CMN_ERROR: u32 = 0x2000_0000;

    // <sys/vnode.h>
    const VREG: u32 = 1;
    const VDIR: u32 = 2;

    const COMMON: u32 = libc::ATTR_CMN_RETURNED_ATTRS
        | libc::ATTR_CMN_NAME
        | ATTR_CMN_ERROR
        | libc::ATTR_CMN_DEVID
        | libc::ATTR_CMN_OBJTYPE
        | libc::ATTR_CMN_MODTIME
        | libc::ATTR_CMN_FLAGS
        | libc::ATTR_CMN_FILEID;
    const FILE: u32 = libc::ATTR_FILE_LINKCOUNT | libc::ATTR_FILE_ALLOCSIZE | libc::ATTR_FILE_DATALENGTH;

    /// Lecture bornée d'un entier dans le tampon ; `None` si le noyau a renvoyé moins que prévu.
    fn u32_at(buf: &[u8], off: usize) -> Option<u32> {
        Some(u32::from_ne_bytes(buf.get(off..off + 4)?.try_into().ok()?))
    }
    fn u64_at(buf: &[u8], off: usize) -> Option<u64> {
        Some(u64::from_ne_bytes(buf.get(off..off + 8)?.try_into().ok()?))
    }

    /// Liste un dossier avec `getattrlistbulk`. `Err` si le dossier n'a pas pu être ouvert ou si
    /// le volume ne prend pas en charge l'appel : l'appelant se replie alors sur `read_dir`.
    const DIR_FLAGS: libc::c_int = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;

    /// Ouvre un dossier. Au-delà de `PATH_MAX` (1 024 octets, ex. `node_modules` très imbriqués),
    /// `open` échoue : on descend alors composant par composant avec `openat`, chaque étape
    /// relative à la précédente et sans suivre de lien (`O_NOFOLLOW` à chaque niveau).
    ///
    /// Limite connue, sans danger : `O_NOFOLLOW` vaut aussi pour les ancêtres. Un chemin aussi long
    /// sous `/var`, `/tmp` ou `/etc` (liens vers `/private/…`) échoue donc (`ELOOP`) et compte 0 ;
    /// le dossier personnel n'est pas concerné. Pour le lever : canoniser le préfixe avant la
    /// descente, jamais en suivant de lien dans la partie profonde.
    fn open_dir(dir: &Path) -> io::Result<libc::c_int> {
        let c = CString::new(dir.as_os_str().as_bytes())?;
        let fd = unsafe { libc::open(c.as_ptr(), DIR_FLAGS) };
        if fd >= 0 {
            return Ok(fd);
        }
        let err = io::Error::last_os_error();
        if err.raw_os_error() != Some(libc::ENAMETOOLONG) || !dir.is_absolute() {
            return Err(err);
        }
        let root = CString::new("/").expect("sans NUL");
        let mut current = Fd(unsafe { libc::open(root.as_ptr(), DIR_FLAGS) });
        if current.0 < 0 {
            return Err(io::Error::last_os_error());
        }
        for comp in dir.components() {
            let name = match comp {
                std::path::Component::RootDir => continue,
                std::path::Component::Normal(n) => CString::new(n.as_bytes())?,
                // `.` ou `..` : jamais dans un chemin produit par le parcours ; on refuse.
                _ => return Err(io::Error::from_raw_os_error(libc::EINVAL)),
            };
            let next = unsafe { libc::openat(current.0, name.as_ptr(), DIR_FLAGS) };
            if next < 0 {
                return Err(io::Error::last_os_error());
            }
            current = Fd(next); // l'ancien descripteur est fermé par Drop
        }
        let fd = current.0;
        std::mem::forget(current);
        Ok(fd)
    }

    pub fn list_bulk(dir: &Path, buf: &mut [u8], on_entry: &mut dyn FnMut(Entry<'_>)) -> io::Result<()> {
        let fd = open_dir(dir);
        if let Err(err) = fd {
            // Droits insuffisants : le repli n'y changerait rien, on ne retente pas.
            return if err.raw_os_error() == Some(libc::EACCES) || err.raw_os_error() == Some(libc::EPERM) {
                Ok(())
            } else {
                Err(err)
            };
        }
        let fd = Fd(fd.expect("erreur traitée ci-dessus"));

        let mut al: libc::attrlist = unsafe { std::mem::zeroed() };
        al.bitmapcount = libc::ATTR_BIT_MAP_COUNT;
        al.commonattr = COMMON;
        al.fileattr = FILE;

        let mut first = true;
        loop {
            let n = unsafe {
                libc::getattrlistbulk(
                    fd.0,
                    &mut al as *mut _ as *mut libc::c_void,
                    buf.as_mut_ptr() as *mut libc::c_void,
                    buf.len(),
                    0,
                )
            };
            if n < 0 {
                let err = io::Error::last_os_error();
                // Non pris en charge par ce volume : repli seulement si rien n'a encore été compté.
                return if first { Err(err) } else { Ok(()) };
            }
            if n == 0 {
                return Ok(());
            }
            first = false;
            let mut off = 0usize;
            for _ in 0..n {
                let Some(len) = parse_entry(&buf[off..], on_entry) else { return Ok(()) };
                off += len;
            }
        }
    }

    /// Décode une entrée et renvoie sa longueur. Les attributs sont présents dans l'ordre de
    /// leurs bits, `ATTR_CMN_ERROR` juste après `ATTR_CMN_RETURNED_ATTRS` (cf. getattrlistbulk(2)).
    fn parse_entry(b: &[u8], on_entry: &mut dyn FnMut(Entry<'_>)) -> Option<usize> {
        let len = u32_at(b, 0)? as usize;
        if len < 24 || len > b.len() {
            return None;
        }
        let b = &b[..len];
        let common = u32_at(b, 4)?;
        let file = u32_at(b, 16)?;
        let mut off = 24; // longueur + attribute_set_t (5 × u32)

        let mut error = 0;
        if common & ATTR_CMN_ERROR != 0 {
            error = u32_at(b, off)?;
            off += 4;
        }
        let mut name: &[u8] = &[];
        if common & libc::ATTR_CMN_NAME != 0 {
            // attrreference_t : décalage relatif à la structure elle-même, longueur NUL inclus.
            let rel = u32_at(b, off)? as i32;
            let n = u32_at(b, off + 4)? as usize;
            let start = (off as isize + rel as isize) as usize;
            name = b.get(start..start + n.saturating_sub(1))?;
            off += 8;
        }
        let mut dev = 0;
        if common & libc::ATTR_CMN_DEVID != 0 {
            // dev_t est un i32 ; même extension de signe que `MetadataExt::dev()`.
            dev = u32_at(b, off)? as i32 as u64;
            off += 4;
        }
        let mut objtype = 0;
        if common & libc::ATTR_CMN_OBJTYPE != 0 {
            objtype = u32_at(b, off)?;
            off += 4;
        }
        let mut modified = 0;
        if common & libc::ATTR_CMN_MODTIME != 0 {
            // struct timespec : tv_sec (i64) puis tv_nsec (i64).
            modified = u64_at(b, off)? as i64;
            off += 16;
        }
        let mut flags = 0;
        if common & libc::ATTR_CMN_FLAGS != 0 {
            flags = u32_at(b, off)?;
            off += 4;
        }
        let mut ino = 0;
        if common & libc::ATTR_CMN_FILEID != 0 {
            ino = u64_at(b, off)?;
            off += 8;
        }
        let mut nlink = 1;
        if file & libc::ATTR_FILE_LINKCOUNT != 0 {
            nlink = u32_at(b, off)? as u64;
            off += 4;
        }
        let mut alloc = 0;
        if file & libc::ATTR_FILE_ALLOCSIZE != 0 {
            alloc = u64_at(b, off)?;
            off += 8;
        }
        let mut data_len = 0;
        if file & libc::ATTR_FILE_DATALENGTH != 0 {
            data_len = u64_at(b, off)?;
        }

        if error == 0 && !name.is_empty() {
            let kind = match objtype {
                VREG => Kind::File,
                VDIR => Kind::Dir,
                _ => Kind::Other,
            };
            on_entry(Entry { name: OsStr::from_bytes(name), kind, dev, ino, nlink, flags, alloc, len: data_len, modified });
        }
        Some(len)
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::Entry;
    use std::path::Path;

    pub fn disable_materialization() {}

    pub fn list_bulk(_: &Path, _: &mut [u8], _: &mut dyn FnMut(Entry<'_>)) -> std::io::Result<()> {
        Err(std::io::ErrorKind::Unsupported.into())
    }
}

#[cfg(test)]
mod tests {
    use super::{Queue, Task};
    use std::path::PathBuf;

    fn task(root: usize, name: &str) -> Task {
        Task { root, path: PathBuf::from(name), device: 0 }
    }

    #[test]
    fn roots_are_served_in_turn_and_depth_first_within_one() {
        let mut q = Queue::new(3);
        // La racine 0 a beaucoup de travail empilé ; 1 et 2 un seul dossier chacune.
        for i in 0..5 {
            q.push(task(0, &format!("a{i}")));
        }
        q.push(task(1, "b0"));
        q.push(task(2, "c0"));
        let order: Vec<String> = std::iter::from_fn(|| q.pop()).map(|t| t.path.display().to_string()).collect();
        // Chaque racine passe dès le premier tour ; la racine 0 reste en profondeur d'abord.
        assert_eq!(order, vec!["a4", "b0", "c0", "a3", "a2", "a1", "a0"]);
    }
}
