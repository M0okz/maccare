//! Utilitaires de chemin **purement lexicaux** (sans accès disque).
//!
//! La normalisation lexicale n'est sûre pour un `starts_with` de confinement que si
//! l'on a par ailleurs établi qu'aucun ancêtre n'est un lien symbolique
//! (voir [`crate::safety`]). On ne résout donc volontairement aucun lien ici.

use std::path::{Component, Path, PathBuf};

/// Normalise un chemin lexicalement : supprime les `.`, résout les `..` au niveau du texte,
/// sans toucher au système de fichiers. Ne garantit pas l'existence du chemin.
pub fn lexical_normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                // Ne remonte pas au-delà d'une racine ni d'un préfixe.
                if matches!(out.components().next_back(), Some(Component::Normal(_))) {
                    out.pop();
                } else {
                    out.push("..");
                }
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Développe un `~` initial en utilisant la variable d'environnement `HOME`.
/// Renvoie le chemin inchangé si `HOME` est absent ou si `~` n'est pas en tête.
pub fn expand_tilde(raw: &str) -> PathBuf {
    if raw == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home);
        }
    }
    if let Some(rest) = raw.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return Path::new(&home).join(rest);
        }
    }
    PathBuf::from(raw)
}

/// Vrai si `path`, normalisé, est égal à `root` normalisé ou situé **sous** lui.
/// Comparaison lexicale : à n'utiliser qu'après la garde anti-symlink.
pub fn is_within(path: &Path, root: &Path) -> bool {
    let p = lexical_normalize(path);
    let r = lexical_normalize(root);
    p == r || p.starts_with(&r)
}
