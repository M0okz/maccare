//! Scanner générique piloté par une règle.
//!
//! Il énumère les candidats sous la racine de la règle, applique les exclusions, puis
//! construit un [`ScanItem`] par candidat retenu. La mesure des tailles est déléguée à
//! [`crate::walk`]. Il **ne supprime rien** et ne présélectionne
//! que selon la politique déclarée par la règle.

use crate::model::{FileIdentity, ScanItem};
use crate::rules::{Depth, Rule};
use crate::walk::{self, Budget, Control};
use std::sync::Arc;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Budget de mesure d'une règle entière. Toutes les entrées sont mesurées ensemble sur un pool
/// partagé ; l'attente s'arrête aussi plus tôt si plus rien n'avance (dossier protégé par la
/// confidentialité, montage réseau ou cloud non réponsif) — un scan ne se fige jamais.
pub const RULE_SCAN_BUDGET: Duration = Duration::from_secs(30);

/// Budget de mesure des chemins explicites du désinstalleur.
const INSPECT_BUDGET: Duration = Duration::from_secs(10);

/// Résultat d'un scan : les éléments retenus et les éventuelles erreurs non bloquantes.
#[derive(Debug, Default)]
pub struct ScanOutcome {
    pub items: Vec<ScanItem>,
    pub warnings: Vec<String>,
    /// Vrai si le scan a été annulé : `items` est alors vide (des tailles partielles induiraient
    /// en erreur).
    pub cancelled: bool,
}

/// Construit un [`ScanItem`] pour un chemin explicite s'il existe et n'est pas un lien
/// symbolique. Utilisé par le désinstalleur, qui connaît ses chemins candidats à l'avance.
pub fn inspect_path(
    path: &Path,
    category: impl Into<crate::model::CategoryId>,
    reason: impl Into<crate::model::RuleId>,
) -> Option<ScanItem> {
    let category = category.into();
    let reason = reason.into();
    inspect_paths(&[path.to_path_buf()], &category, &reason).pop()
}

/// Version groupée de [`inspect_path`] : tous les chemins sont mesurés en parallèle.
/// Les chemins absents ou symboliques sont omis ; l'ordre des autres est conservé.
pub fn inspect_paths(paths: &[PathBuf], category: &str, reason: &str) -> Vec<ScanItem> {
    let candidates: Vec<(PathBuf, FileIdentity)> = paths
        .iter()
        .filter_map(|p| {
            let md = std::fs::symlink_metadata(p).ok()?;
            if md.file_type().is_symlink() {
                return None;
            }
            Some((p.clone(), FileIdentity::of_path(p).ok()?))
        })
        .collect();
    let roots: Vec<PathBuf> = candidates.iter().map(|(p, _)| p.clone()).collect();
    let sizes = walk::measure_paths(&roots, Budget::new(INSPECT_BUDGET));

    candidates
        .into_iter()
        .zip(sizes)
        .map(|((path, identity), m)| ScanItem::new(path, category, reason, m.bytes, false, identity))
        .collect()
}

/// Exécute un scan pour une règle donnée.
pub fn scan_rule(rule: &Rule) -> ScanOutcome {
    scan_rule_with_budget(rule, Budget::new(RULE_SCAN_BUDGET))
}

/// [`scan_rule`] avec un budget explicite (tests, appelants pressés).
pub fn scan_rule_with_budget(rule: &Rule, budget: Budget) -> ScanOutcome {
    scan_rule_with(rule, budget, &Control::new())
}

/// [`scan_rule`] sous un [`Control`] : annulable, progression observable pendant le scan.
pub fn scan_rule_with(rule: &Rule, budget: Budget, control: &Arc<Control>) -> ScanOutcome {
    let mut outcome = ScanOutcome::default();
    let root = rule.root_path();

    let entries = match std::fs::read_dir(&root) {
        Ok(e) => e,
        Err(e) => {
            // Racine absente ou inaccessible : ce n'est pas une erreur fatale.
            outcome
                .warnings
                .push(format!("racine inaccessible {} : {e}", root.display()));
            return outcome;
        }
    };

    // 1. Sélection des candidats, sans rien mesurer : tous les filtres bon marché d'abord.
    let mut candidates: Vec<(PathBuf, FileIdentity, Option<String>)> = Vec::new();
    for entry in entries.flatten() {
        if control.is_cancelled() {
            break;
        }
        let path = entry.path();

        // En profondeur Flat, on ne retient que les fichiers directs ; en PerApp, les entrées
        // directes (dossiers ou fichiers) sont chacune un candidat.
        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if file_type.is_symlink() {
            continue; // on ne propose jamais un lien symbolique
        }
        if matches!(rule.depth, Depth::Flat) && !file_type.is_file() {
            continue;
        }

        // Prédicats d'inclusion (par exemple un suffixe de fichier) : tout aussi bon marché.
        if !rule.included(&path) {
            continue;
        }

        // Les exclusions par nom/chemin sont bon marché : on les applique AVANT de mesurer,
        // pour ne jamais descendre (ni se bloquer) dans un dossier qu'on écarte de toute façon
        // — typiquement les caches Apple (préfixe `com.apple.`), protégés par TCC.
        if rule.ignored_by_name(&path) {
            continue;
        }

        // Repère exigé (ex. app Electron) : sans lui, l'entrée est écartée.
        if !rule.has_marker(&path) {
            continue;
        }

        // L'entrée elle-même, ou ses sous-chemins déclarés : chacun doit être un vrai dossier ou
        // fichier, sans aucun lien symbolique entre l'entrée et lui.
        for candidate in rule.candidates_of(&path) {
            if candidate != path {
                if !crate::safety::no_symlink_between(&path, &candidate) {
                    continue;
                }
                if rule.ignored_by_name(&candidate) {
                    continue;
                }
            }
            let owner = (candidate != path).then(|| entry.file_name().to_string_lossy().into_owned());
            match FileIdentity::of_path(&candidate) {
                Ok(id) => candidates.push((candidate, id, owner)),
                Err(_) => continue, // sans identité, pas de candidat (il ne pourrait pas être validé)
            }
        }
    }

    // 2. Mesure groupée sur un pool partagé.
    let roots: Vec<PathBuf> = candidates.iter().map(|(p, _, _)| p.clone()).collect();
    let sizes = walk::measure_paths_with(&roots, budget, control);
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }

    // 3. Filtres dépendant de la taille, puis construction des éléments.
    for ((path, identity, owner), m) in candidates.into_iter().zip(sizes) {
        // Entièrement mesuré et vide : rien à libérer, on ne l'affiche pas.
        if m.complete && m.bytes == 0 {
            continue;
        }
        if !m.complete {
            if m.bytes == 0 {
                // Rien n'a pu être lu : probablement bloqué (TCC, montage). On ne propose pas
                // un élément dont on ne sait rien.
                outcome
                    .warnings
                    .push(format!("ignoré (mesure bloquée) {}", path.display()));
                continue;
            }
            // Taille partielle : c'est une borne inférieure, l'élément reste nettoyable.
            outcome
                .warnings
                .push(format!("taille partielle (mesure interrompue) {}", path.display()));
        }
        if rule.should_ignore(&path, m.bytes) {
            continue;
        }
        let mut item = ScanItem::new(path, rule.category.clone(), rule.id.clone(), m.bytes, rule.autoselect, identity);
        item.owner = owner;
        outcome.items.push(item);
    }

    outcome
}

// ---------------------------------------------------------------------------
// Exploration de l'espace disque (module « Espace disque »).
// ---------------------------------------------------------------------------

/// Un enfant direct d'un dossier exploré, avec sa taille.
#[derive(Debug, Clone)]
pub struct DirChild {
    pub path: PathBuf,
    pub size_bytes: u64,
    pub is_dir: bool,
    /// Faux si la mesure a dépassé le budget (taille non fiable, à signaler dans l'UI).
    pub measured: bool,
}

/// Résultat d'une mesure d'un niveau de dossier.
#[derive(Debug, Default)]
pub struct MeasureOutcome {
    pub children: Vec<DirChild>,
    pub warnings: Vec<String>,
    /// Vrai si la mesure a été annulée : `children` est alors vide.
    pub cancelled: bool,
}

/// Budget global par défaut pour mesurer un niveau de dossier.
pub const MEASURE_DEFAULT_BUDGET: Duration = Duration::from_secs(20);

/// Mesure les enfants **directs** d'un dossier, triés par taille décroissante.
///
/// Tous les sous-dossiers sont mesurés ensemble sur un pool borné, avant une **échéance
/// globale** : un enfant non terminé est renvoyé avec sa taille partielle et `measured = false`
/// plutôt que de figer tout le niveau (cf. caches protégés par TCC ou montages non réponsifs).
/// Les liens symboliques sont listés mais jamais suivis (taille 0).
pub fn measure_children(dir: &Path, budget: Duration) -> MeasureOutcome {
    measure_children_with(dir, budget, &Control::new())
}

/// [`measure_children`] sous un [`Control`] : annulable, progression observable.
/// macOS présente les données utilisateur dans l’arbre du volume système via des firmlinks.
/// Seuls les chemins du manifeste système sont admis ; /Volumes reste une frontière de montage.
fn parse_startup_firmlinks(source: &str) -> std::collections::HashSet<PathBuf> {
    source.lines().filter_map(|line| {
        let path = PathBuf::from(line.split_whitespace().next()?);
        if !path.is_absolute() || path == Path::new("/Volumes")
            || path.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
            return None;
        }
        Some(path)
    }).collect()
}

pub fn measure_children_with(dir: &Path, budget: Duration, control: &Arc<Control>) -> MeasureOutcome {
    let mut outcome = MeasureOutcome::default();

    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            outcome
                .warnings
                .push(format!("dossier inaccessible {} : {e}", dir.display()));
            return outcome;
        }
    };

    // Les fichiers (et liens) sont mesurés immédiatement ; les dossiers vont au pool.
    let mut children: Vec<DirChild> = Vec::new();
    let mut dirs: Vec<PathBuf> = Vec::new();
    let dir_device = std::fs::metadata(dir).ok().map(|m| m.dev());
    let firmlinks = std::fs::read_to_string("/usr/share/firmlinks")
        .map(|text| parse_startup_firmlinks(&text)).unwrap_or_default();

    for entry in entries.flatten() {
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };

        if file_type.is_symlink() {
            children.push(DirChild { path, size_bytes: 0, is_dir: false, measured: true });
        } else if file_type.is_dir() {
            // Point de montage (autre volume, ex. partage réseau) : on ne le mesure pas. Un
            // montage réseau injoignable bloquerait la lecture, et ce n'est pas ce disque.
            let other_volume = match (dir_device, entry.metadata()) {
                (Some(parent), Ok(md)) => md.dev() != parent,
                _ => false,
            };
            if other_volume && !firmlinks.contains(&path) {
                outcome
                    .warnings
                    .push(format!("autre volume, non mesuré : {}", path.display()));
                children.push(DirChild { path, size_bytes: 0, is_dir: true, measured: false });
            } else {
                dirs.push(path);
            }
        } else {
            let size = entry.metadata().map(|m| walk::allocated_size(&m)).unwrap_or(0);
            children.push(DirChild { path, size_bytes: size, is_dir: false, measured: true });
        }
    }

    let sizes = walk::measure_paths_with(&dirs, Budget::new(budget), control);
    if control.is_cancelled() {
        outcome.cancelled = true;
        return outcome;
    }
    for (path, m) in dirs.into_iter().zip(sizes) {
        if !m.complete {
            outcome
                .warnings
                .push(format!("mesure interrompue (budget) {}", path.display()));
        }
        // Le parcours d’un enfant ne traverse pas les changements de volume internes.
        // Si cet enfant contient un firmlink imbriqué (System, usr), son total est un minimum.
        let nested_firmlink = firmlinks.iter().any(|link| link != &path && link.starts_with(&path));
        children.push(DirChild { path, size_bytes: m.bytes, is_dir: true, measured: m.complete && !nested_firmlink });
    }

    children.sort_by_key(|c| std::cmp::Reverse(c.size_bytes));
    outcome.children = children;
    outcome
}

#[cfg(test)]
mod startup_firmlink_tests {
    use super::*;

    #[test]
    fn only_absolute_manifest_paths_except_volume_mounts_are_admitted() {
        let paths = parse_startup_firmlinks("/Users\tUsers\n/Applications\tApplications\n/Volumes\tVolumes\nrelative\tother\n/Users/../outside\toutside\n");
        assert!(paths.contains(Path::new("/Users")));
        assert!(paths.contains(Path::new("/Applications")));
        assert_eq!(paths.len(), 2);
    }
}
