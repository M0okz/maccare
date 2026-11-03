//! Chargement et évaluation des règles de nettoyage (format ouvert).
//!
//! Une règle est un fichier TOML versionné dans le dépôt. Elle décrit **où** chercher,
//! **à quelle profondeur**, et **quels éléments exclure**. Une règle invalide est rejetée
//! au chargement : elle n'est jamais appliquée à moitié.

use crate::path_util;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Profondeur d'énumération d'un scanner à partir de la racine de la règle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Depth {
    /// Un niveau : chaque entrée directe (typiquement un dossier par application).
    PerApp,
    /// Fichiers directement sous la racine.
    Flat,
}

impl Default for Depth {
    fn default() -> Self {
        Depth::PerApp
    }
}

/// Niveau de risque d'une règle : décide de la présélection et du badge affiché.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "kebab-case")]
pub enum Risk {
    /// Régénérable sans conséquence (caches, logs).
    #[default]
    Safe,
    /// Données de l'utilisateur possibles : toujours à confirmer, jamais coché d'office.
    Review,
}

/// Public d'une règle : tout le monde, ou seulement les utilisateurs qui ont activé les outils
/// pour développeurs dans l'app (Xcode, simulateurs…).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "kebab-case")]
pub enum Audience {
    #[default]
    Everyone,
    Developer,
}

/// Un prédicat d'inclusion. Si une règle en déclare, un candidat doit en satisfaire au moins un.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum Include {
    /// Dernier composant du chemin se terminant par `ends_with` (insensible à la casse).
    NameSuffix { ends_with: String },
    /// Fichier `.plist` dont le contenu **ne s'analyse pas** (préférence corrompue). Voir
    /// [`is_broken_plist`] : une erreur de lecture ne compte jamais.
    InvalidPlist,
}

/// Délai sous lequel un fichier vient d'être écrit (cfprefsd peut être en train de le réécrire).
const RECENT: std::time::Duration = std::time::Duration::from_secs(60);

/// Vrai si `path` est un `.plist` ordinaire, non vide, inchangé depuis une minute, **lisible**, et
/// dont le contenu n'est pas un plist valide. Toute incertitude (lecture refusée, fichier vide ou
/// en cours d'écriture) renvoie faux : on ne déclare jamais cassé ce qu'on n'a pas pu lire.
pub fn is_broken_plist(path: &Path) -> bool {
    let is_plist = path
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("plist"));
    let Ok(md) = std::fs::symlink_metadata(path) else { return false };
    let settled = md
        .modified()
        .ok()
        .and_then(|m| m.elapsed().ok())
        .is_some_and(|age| age >= RECENT);
    if !is_plist || !md.is_file() || md.len() == 0 || !settled {
        return false;
    }
    let Ok(bytes) = std::fs::read(path) else { return false };
    plist::Value::from_reader(std::io::Cursor::new(bytes)).is_err()
}

impl Include {
    /// Vrai si le candidat satisfait ce prédicat.
    pub fn matches(&self, path: &Path) -> bool {
        match self {
            Include::NameSuffix { ends_with } => path
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.to_lowercase().ends_with(&ends_with.to_lowercase()))
                .unwrap_or(false),
            Include::InvalidPlist => is_broken_plist(path),
        }
    }
}

/// Un prédicat d'exclusion. Si l'un s'applique, le candidat est écarté.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum Exclude {
    /// Dernier composant du chemin égal à `equals`.
    Name { equals: String },
    /// Dernier composant du chemin commençant par `starts_with`
    /// (ex. `"com.apple."` pour écarter les bundles Apple).
    NamePrefix { starts_with: String },
    /// Chemin situé dans l'arbre de ce préfixe (comparaison **par composant**, `~` développé).
    PathPrefix { value: String },
    /// Taille inférieure ou égale à `bytes` (écarte les éléments trop petits).
    MaxSize { bytes: u64 },
}

impl Exclude {
    /// Vrai si ce prédicat impose d'ignorer le candidat.
    pub fn should_ignore(&self, path: &Path, size_bytes: u64) -> bool {
        match self {
            Exclude::Name { equals } => path
                .file_name()
                .map(|n| n == equals.as_str())
                .unwrap_or(false),
            Exclude::NamePrefix { starts_with } => path
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with(starts_with.as_str()))
                .unwrap_or(false),
            Exclude::PathPrefix { value } => {
                path_util::is_within(path, &path_util::expand_tilde(value))
            }
            Exclude::MaxSize { bytes } => size_bytes <= *bytes,
        }
    }

    /// Vrai si ce prédicat a besoin de mesurer la taille du candidat sur disque.
    fn needs_size(&self) -> bool {
        matches!(self, Exclude::MaxSize { .. })
    }
}

/// Une règle de nettoyage complète.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Rule {
    pub id: String,
    pub category: String,
    pub version: u32,
    /// Racine de recherche ; le `~` est développé via `HOME`.
    pub root: String,
    #[serde(default)]
    pub depth: Depth,
    #[serde(default)]
    pub autoselect: bool,
    #[serde(default)]
    pub exclude: Vec<Exclude>,
    /// Si non vide, un candidat doit satisfaire au moins un de ces prédicats.
    #[serde(default)]
    pub include: Vec<Include>,
    /// Sous-chemins proposés **dans** chaque entrée de la racine, au lieu de l'entrée elle-même
    /// (ex. `"Data/Library/Caches"` dans chaque conteneur d'app). Relatifs, sans `..`.
    #[serde(default)]
    pub subpaths: Vec<String>,
    /// Si non vide, une entrée n'est retenue que si elle contient au moins un de ces noms
    /// (repère d'un type d'app, ex. `"Local State"` pour les apps Electron).
    #[serde(default)]
    pub require_any: Vec<String>,
    /// Public visé (voir [`Audience`]).
    #[serde(default)]
    pub audience: Audience,

    // --- Présentation (facultative, pour les interfaces) ---
    /// Nom affiché ; à défaut, l'interface retombe sur l'identifiant.
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub risk: Risk,
    /// Nom de symbole SF Symbols, indicatif.
    #[serde(default)]
    pub icon: String,
    /// Vrai si l'interface peut appliquer un seuil de taille minimale réglable par l'utilisateur.
    #[serde(default)]
    pub min_size_setting: bool,
}

/// Erreur de chargement d'une règle.
#[derive(Debug)]
pub enum RuleError {
    Parse(toml::de::Error),
    Invalid(String),
}

impl std::fmt::Display for RuleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RuleError::Parse(e) => write!(f, "règle illisible : {e}"),
            RuleError::Invalid(m) => write!(f, "règle invalide : {m}"),
        }
    }
}

impl std::error::Error for RuleError {}

impl Rule {
    /// Charge et valide une règle depuis une chaîne TOML.
    pub fn from_toml(src: &str) -> Result<Rule, RuleError> {
        let rule: Rule = toml::from_str(src).map_err(RuleError::Parse)?;
        rule.validate()?;
        Ok(rule)
    }

    fn validate(&self) -> Result<(), RuleError> {
        if self.id.trim().is_empty() {
            return Err(RuleError::Invalid("id vide".into()));
        }
        if self.category.trim().is_empty() {
            return Err(RuleError::Invalid("category vide".into()));
        }
        if self.root.trim().is_empty() {
            return Err(RuleError::Invalid("root vide".into()));
        }
        let plain = |s: &str| {
            let p = Path::new(s);
            !s.trim().is_empty()
                && p.components().all(|c| matches!(c, std::path::Component::Normal(_)))
        };
        if let Some(bad) = self.subpaths.iter().find(|s| !plain(s)) {
            return Err(RuleError::Invalid(format!("sous-chemin invalide : {bad:?}")));
        }
        if let Some(bad) = self.require_any.iter().find(|s| !plain(s) || s.contains('/')) {
            return Err(RuleError::Invalid(format!("repère invalide : {bad:?}")));
        }
        if !self.subpaths.is_empty() && matches!(self.depth, Depth::Flat) {
            return Err(RuleError::Invalid("subpaths incompatible avec depth = flat".into()));
        }
        Ok(())
    }

    /// Racine développée (le `~` résolu).
    pub fn root_path(&self) -> PathBuf {
        path_util::expand_tilde(&self.root)
    }

    /// Vrai si un candidat de taille donnée doit être écarté par au moins un prédicat.
    pub fn should_ignore(&self, path: &Path, size_bytes: u64) -> bool {
        self.exclude.iter().any(|e| e.should_ignore(path, size_bytes))
    }

    /// Vrai si l'entrée porte un des repères exigés (ou s'il n'y en a aucun). Sans suivre de lien.
    pub fn has_marker(&self, entry: &Path) -> bool {
        self.require_any.is_empty()
            || self.require_any.iter().any(|m| std::fs::symlink_metadata(entry.join(m)).is_ok())
    }

    /// Candidats d'une entrée de la racine : l'entrée elle-même, ou ses sous-chemins déclarés.
    pub fn candidates_of(&self, entry: &Path) -> Vec<PathBuf> {
        if self.subpaths.is_empty() {
            vec![entry.to_path_buf()]
        } else {
            self.subpaths.iter().map(|s| entry.join(s)).collect()
        }
    }

    /// Vrai si le candidat satisfait les prédicats d'inclusion (ou s'il n'y en a aucun).
    pub fn included(&self, path: &Path) -> bool {
        self.include.is_empty() || self.include.iter().any(|i| i.matches(path))
    }

    /// Vrai si un prédicat **indépendant de la taille** (nom, préfixe de nom, préfixe de chemin)
    /// écarte déjà ce candidat. Permet de l'ignorer sans mesurer sa taille — donc sans descendre
    /// dans un dossier potentiellement bloquant.
    pub fn ignored_by_name(&self, path: &Path) -> bool {
        self.exclude
            .iter()
            .filter(|e| !e.needs_size())
            .any(|e| e.should_ignore(path, 0))
    }
}
