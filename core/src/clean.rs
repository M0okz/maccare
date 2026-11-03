//! Exécuteur de nettoyage.
//!
//! Il **re-valide** chaque élément via [`crate::safety::evaluate`] immédiatement avant d'agir.
//! Par défaut il n'effectue aucune suppression : la mise à la corbeille est faite côté Swift,
//! sur la seule liste d'éléments déclarés `Allowed` ici. Le mode [`RemovalMode::DirectDelete`]
//! existe pour les tests et une future option explicite, jamais activé par défaut.

use crate::model::ScanItem;
use crate::rules::Rule;
use crate::safety::{self, Decision, SafetyContext};
use std::path::{Path, PathBuf};

/// Mode d'exécution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemovalMode {
    /// Valide seulement ; ne touche pas au disque. Les éléments autorisés sont destinés
    /// à la corbeille côté application.
    DryRun,
    /// Supprime directement les éléments autorisés. Option explicite et irréversible.
    DirectDelete,
}

/// Issue de l'exécution pour un élément.
#[derive(Debug)]
pub struct CleanResult {
    pub path: PathBuf,
    pub decision: Decision,
    /// Vrai uniquement si une suppression effective a eu lieu (mode `DirectDelete`).
    pub removed: bool,
    pub error: Option<String>,
}

/// Valide une liste d'éléments et, selon le mode, les supprime. L'ordre d'évaluation est
/// préservé ; un refus n'interrompt pas le traitement des suivants.
pub fn execute(
    ctx: &SafetyContext,
    scope_root: &Path,
    items: &[ScanItem],
    mode: RemovalMode,
) -> Vec<CleanResult> {
    items
        .iter()
        .map(|item| {
            let decision = safety::evaluate(ctx, &item.path, scope_root, item.identity);
            run_one(decision, item, mode)
        })
        .collect()
}

/// Comme [`execute`], mais chaque élément est re-validé contre la règle qui l'a proposé
/// ([`safety::evaluate_for_rule`]) : la racine de la règle sert de périmètre.
pub fn execute_for_rule(
    ctx: &SafetyContext,
    rule: &Rule,
    items: &[ScanItem],
    mode: RemovalMode,
) -> Vec<CleanResult> {
    items
        .iter()
        .map(|item| {
            let decision = safety::evaluate_for_rule(ctx, &item.path, rule, item.identity);
            run_one(decision, item, mode)
        })
        .collect()
}

fn run_one(decision: Decision, item: &ScanItem, mode: RemovalMode) -> CleanResult {
    if !decision.is_allowed() {
        return CleanResult {
            path: item.path.clone(),
            decision,
            removed: false,
            error: None,
        };
    }

    match mode {
        RemovalMode::DryRun => CleanResult {
            path: item.path.clone(),
            decision,
            removed: false,
            error: None,
        },
        RemovalMode::DirectDelete => {
            let res = remove_path(&item.path);
            let (removed, error) = match res {
                Ok(()) => (true, None),
                Err(e) => (false, Some(e.to_string())),
            };
            CleanResult {
                path: item.path.clone(),
                decision,
                removed,
                error,
            }
        }
    }
}

fn remove_path(path: &Path) -> std::io::Result<()> {
    let md = std::fs::symlink_metadata(path)?;
    if md.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    }
}
