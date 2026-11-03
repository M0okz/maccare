//! Gros fichiers du dossier personnel (module « Gros fichiers »).
//!
//! Recherche les plus gros fichiers sous une racine du dossier personnel, sur le même parcours
//! parallèle que les mesures ([`crate::walk`]). Ce sont des **documents de l'utilisateur** : rien
//! n'est présélectionné, et seule la mise à la corbeille est prévue (voir
//! [`safety::evaluate_user_file`]).
//!
//! Sont écartés d'emblée, à la recherche comme à la validation : `~/Library` (données d'apps, dont
//! la suppression d'un fichier isolé casse l'app), les entrées cachées et le contenu des paquets
//! (`.app`, bibliothèque Photos…), qui n'ont de sens qu'entiers.

use crate::model::FileIdentity;
use crate::path_util;
use crate::safety::{self, Decision, Refusal, SafetyContext};
use crate::walk::{self, Budget, Control, WalkOptions};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

/// Seuil par défaut : 50 Mio.
pub const DEFAULT_MIN_BYTES: u64 = 50 * 1024 * 1024;
/// Nombre maximal de fichiers rendus par défaut (les plus gros).
pub const DEFAULT_LIMIT: usize = 500;
/// Budget par défaut d'une recherche.
pub const DEFAULT_BUDGET: Duration = Duration::from_secs(180);

/// Un gros fichier trouvé.
#[derive(Debug, Clone, serde::Serialize)]
pub struct LargeFile {
    pub path: PathBuf,
    pub size_bytes: u64,
    /// Dernière modification, en secondes depuis l'époque Unix.
    pub modified: i64,
    pub identity: FileIdentity,
}

/// Résultat d'une recherche.
#[derive(Debug, Default)]
pub struct LargeOutcome {
    /// Triés par taille décroissante.
    pub files: Vec<LargeFile>,
    pub warnings: Vec<String>,
    /// Faux si la recherche a été interrompue (échéance ou blocage) : liste partielle.
    pub complete: bool,
    /// Vrai si l'utilisateur a annulé : `files` est alors vide.
    pub cancelled: bool,
}

fn home() -> Option<PathBuf> {
    std::env::var("HOME").ok().map(|h| path_util::lexical_normalize(Path::new(&h)))
}

/// Arbres exclus : la bibliothèque de l'utilisateur.
fn excluded() -> Vec<PathBuf> {
    home().map(|h| vec![h.join("Library")]).unwrap_or_default()
}

/// Vrai si les composants de `rel` sont tous ordinaires, non cachés, et qu'aucun paquet ne les
/// contient. `last_may_be_package` : le dernier composant peut lui-même être un paquet (un
/// fichier `.pkg`, par exemple), mais on ne descend jamais dans un paquet.
fn plain_components(rel: &Path, last_may_be_package: bool) -> bool {
    let parts: Vec<_> = rel.components().collect();
    parts.iter().enumerate().all(|(i, c)| match c {
        Component::Normal(name) => {
            let hidden = name.as_encoded_bytes().first() == Some(&b'.');
            let last = i + 1 == parts.len();
            let package = walk::is_package_name(name) && !(last && last_may_be_package);
            !hidden && !package
        }
        _ => false,
    })
}

/// Vérifie qu'une racine de recherche est admise : le dossier personnel ou un de ses
/// sous-dossiers, hors `~/Library`, sans composant caché (`~/.ssh`, `~/.aws`…) ni paquet entre
/// le dossier personnel et elle. Renvoie la racine normalisée.
pub fn validate_root(root: &Path) -> Result<PathBuf, String> {
    let home = home().ok_or("HOME indéfini")?;
    let root = path_util::lexical_normalize(root);
    if !path_util::is_within(&root, &home) {
        return Err(format!("racine hors du dossier personnel : {}", root.display()));
    }
    if excluded().iter().any(|x| path_util::is_within(&root, x)) {
        return Err(format!("racine exclue : {}", root.display()));
    }
    let rel = root.strip_prefix(&home).unwrap_or(Path::new(""));
    if !plain_components(rel, false) {
        return Err(format!("racine cachée ou dans un paquet : {}", root.display()));
    }
    Ok(root)
}

/// Vrai si `path` est un fichier que ce module peut proposer sous `root` : sous la racine, hors
/// `~/Library`, sans composant caché ni paquet entre la racine et lui. Purement lexical.
///
/// Le contrôle porte aussi sur tout le chemin **depuis le dossier personnel** : la garantie ne
/// dépend pas de la racine fournie par l'appelant (une racine `~/.ssh` ne rend pas `id_ed25519`
/// éligible).
pub fn is_eligible(path: &Path, root: &Path) -> bool {
    let path = path_util::lexical_normalize(path);
    let Ok(rel) = path.strip_prefix(path_util::lexical_normalize(root)) else { return false };
    if rel.as_os_str().is_empty() || !plain_components(rel, true) {
        return false;
    }
    if excluded().iter().any(|x| path_util::is_within(&path, x)) {
        return false;
    }
    match home() {
        Some(home) => match path.strip_prefix(&home) {
            Ok(from_home) => plain_components(from_home, true),
            Err(_) => true, // hors du dossier personnel : seule la racine fait foi (tests)
        },
        None => true,
    }
}

/// Validation d'un retrait pour ce module : éligibilité, puis [`safety::evaluate_user_file`].
pub fn evaluate(ctx: &SafetyContext, path: &Path, root: &Path, expected: FileIdentity) -> Decision {
    if !is_eligible(path, root) {
        return Decision::Refused(Refusal::NotEligible(path.to_path_buf()));
    }
    safety::evaluate_user_file(ctx, path, root, expected)
}

/// Recherche les fichiers d'au moins `min_bytes` octets alloués sous `root`, les `limit` plus gros.
pub fn find_large_files(
    root: &Path,
    min_bytes: u64,
    limit: usize,
    budget: Budget,
    control: &Arc<Control>,
) -> LargeOutcome {
    let mut outcome = LargeOutcome::default();
    let options = WalkOptions {
        skip_hidden: true,
        skip_packages: true,
        exclude: excluded(),
        collect_min: Some(min_bytes.max(1)),
        skip_projects: false,
    };
    let result = walk::walk_paths(&[root.to_path_buf()], budget, control, options);
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }
    outcome.complete = result.sizes.first().is_some_and(|m| m.complete);
    if !outcome.complete {
        outcome
            .warnings
            .push(format!("recherche interrompue (budget) : liste partielle sous {}", root.display()));
    }

    let mut found = result.found;
    found.sort_by_key(|f| std::cmp::Reverse(f.bytes));
    for f in found {
        if outcome.files.len() >= limit {
            break;
        }
        // Identité relue sans suivre de lien : c'est elle qui sera revérifiée avant la corbeille.
        let Ok(md) = std::fs::symlink_metadata(&f.path) else { continue };
        if !md.file_type().is_file() || !is_eligible(&f.path, root) {
            continue;
        }
        let Ok(identity) = FileIdentity::of_path(&f.path) else { continue };
        outcome.files.push(LargeFile { path: f.path, size_bytes: f.bytes, modified: f.modified, identity });
    }
    outcome
}
