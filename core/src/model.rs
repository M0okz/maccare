//! Modèle de données partagé par le moteur.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Identifiant d'une catégorie de nettoyage (ex. `"user-cache"`).
pub type CategoryId = String;
/// Identifiant d'une règle (ex. `"cache.generic"`).
pub type RuleId = String;

/// Identité stable d'un fichier sur le disque.
///
/// Capturée au moment du scan et **re-vérifiée avant toute suppression**. Si le couple
/// `(device, inode)` a changé entre les deux, l'élément n'est pas celui qui a été scanné
/// et le retrait est refusé.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileIdentity {
    pub device: u64,
    pub inode: u64,
}

impl FileIdentity {
    /// Lit l'identité **sans suivre** un éventuel lien symbolique final.
    pub fn of_path(path: &Path) -> std::io::Result<Self> {
        use std::os::unix::fs::MetadataExt;
        let md = std::fs::symlink_metadata(path)?;
        Ok(FileIdentity {
            device: md.dev(),
            inode: md.ino(),
        })
    }
}

/// Un élément candidat au nettoyage, produit par un scanner.
///
/// `autoselect` reflète la politique de la règle, pas l'état final coché par l'utilisateur :
/// la sélection effective est décidée dans l'UI, jamais imposée par le moteur.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanItem {
    pub id: String,
    pub path: PathBuf,
    pub category: CategoryId,
    pub size_bytes: u64,
    /// Règle qui a retenu cet élément — permet d'expliquer « pourquoi proposé ».
    pub reason: RuleId,
    pub autoselect: bool,
    pub identity: FileIdentity,
    /// Entrée de la racine à laquelle appartient l'élément quand la règle propose un sous-chemin
    /// (ex. `com.tinyspeck.slackmacgap` pour `…/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches`).
    /// Sert à l'affichage : le dernier composant (« Caches ») ne dit pas de quelle app il s'agit.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(default)]
    pub children: Vec<ScanItem>,
}

impl ScanItem {
    pub fn new(
        path: PathBuf,
        category: impl Into<CategoryId>,
        reason: impl Into<RuleId>,
        size_bytes: u64,
        autoselect: bool,
        identity: FileIdentity,
    ) -> Self {
        ScanItem {
            id: uuid::Uuid::new_v4().to_string(),
            path,
            category: category.into(),
            size_bytes,
            reason: reason.into(),
            autoselect,
            identity,
            owner: None,
            children: Vec::new(),
        }
    }
}
