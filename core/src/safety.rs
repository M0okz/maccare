//! Gardes de sûreté. **Point de passage obligatoire avant toute suppression.**
//!
//! Chaque garde échoue fermé (*fail-closed*) : à la moindre incertitude — statut illisible,
//! lien symbolique inattendu, identité changée — la décision est [`Decision::Refused`].
//! C'est le durcissement principal par rapport au binaire analysé, qui absorbait certaines
//! erreurs d'inspection et testait l'appartenance protégée de façon exacte (non récursive).

use crate::model::FileIdentity;
use crate::path_util;
use crate::rules::{Depth, Rule};
use std::path::{Path, PathBuf};

/// Raison d'un refus, pour journalisation et affichage.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Refusal {
    /// Un composant ou un ancêtre du chemin est un lien symbolique.
    SymlinkInPath(PathBuf),
    /// Impossible de lire le statut d'un composant (fail-closed).
    StatError(PathBuf),
    /// Le chemin sort du périmètre déclaré par la règle.
    OutsideScope { path: PathBuf, scope: PathBuf },
    /// Le chemin tombe dans un arbre protégé (comparaison récursive).
    Protected(PathBuf),
    /// L'identité (device, inode) diffère de celle capturée au scan.
    IdentityChanged { expected: FileIdentity, actual: Option<FileIdentity> },
    /// L'élément ne correspond plus à la règle qui l'a proposé (voir [`evaluate_for_rule`]).
    RuleMismatch(PathBuf),
    /// Hors des fichiers que le module concerné peut proposer (ex. pas un fichier ordinaire,
    /// caché, dans un paquet ou dans `~/Library` pour les gros fichiers).
    NotEligible(PathBuf),
    /// Aucun exemplaire conservé, présent et inchangé, ne garantirait qu'une copie subsiste.
    NoKeptCopy(PathBuf),
    /// Le contenu ne correspond plus (ou pas) à celui de l'exemplaire conservé.
    NotDuplicate(PathBuf),
}

/// Décision rendue par [`evaluate`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Allowed,
    Refused(Refusal),
}

impl Decision {
    pub fn is_allowed(&self) -> bool {
        matches!(self, Decision::Allowed)
    }
}

/// Une entrée protégée, avec son mode.
#[derive(Debug, Clone)]
struct ProtectedPath {
    path: PathBuf,
    /// `true` : tout l'arbre est protégé. `false` : seul ce dossier précis l'est, ses enfants
    /// restant supprimables (ex. `~/Library/Containers`, dont le désinstalleur retire un sous-dossier).
    recursive: bool,
}

/// Contexte de sûreté : l'ensemble des chemins protégés et leur mode.
#[derive(Debug, Clone)]
pub struct SafetyContext {
    protected: Vec<ProtectedPath>,
    /// Arbres de documents de l'utilisateur (Documents, Bureau…). Ils restent protégés partout ;
    /// seule [`evaluate_user_file`] — la sélection explicite d'un fichier, mise à la corbeille —
    /// peut y atteindre un fichier.
    user_data: Vec<PathBuf>,
}

impl SafetyContext {
    /// Construit un contexte où chaque racine fournie est protégée **récursivement**.
    pub fn new(protected: impl IntoIterator<Item = PathBuf>) -> Self {
        Self::with_entries(protected.into_iter().map(|p| (p, true)))
    }

    /// Construit un contexte à partir de couples `(chemin, récursif)`.
    pub fn with_entries(entries: impl IntoIterator<Item = (PathBuf, bool)>) -> Self {
        let protected = entries
            .into_iter()
            .map(|(p, recursive)| ProtectedPath {
                path: path_util::lexical_normalize(&p),
                recursive,
            })
            .collect();
        SafetyContext { protected, user_data: Vec::new() }
    }

    /// Déclare des arbres protégés comme « documents de l'utilisateur » (voir [`evaluate_user_file`]).
    /// Ils doivent déjà figurer parmi les entrées protégées : cela ne retire aucune protection.
    pub fn with_user_data(mut self, roots: impl IntoIterator<Item = PathBuf>) -> Self {
        self.user_data = roots.into_iter().map(|p| path_util::lexical_normalize(&p)).collect();
        self
    }

    /// Ensemble protégé par défaut, dérivé de l'environnement courant.
    ///
    /// Distingue deux modes :
    /// - **récursif** : arbres qu'on ne doit jamais toucher (système, Trousseau, dossiers de
    ///   documents de l'utilisateur) ;
    /// - **exact** : dossiers qu'on ne doit pas supprimer *en entier*, mais dont les enfants
    ///   restent légitimement nettoyables ou désinstallables (`~`, `~/Library`, `Preferences`,
    ///   `Containers`, `Application Support`…).
    ///
    /// Un scanner reste de plus confiné sous la racine de sa règle : seconde barrière indépendante.
    pub fn default_for_env() -> Self {
        // (chemin, récursif)
        let mut user_data: Vec<PathBuf> = Vec::new();
        let mut entries: Vec<(PathBuf, bool)> = vec![
            (PathBuf::from("/"), false), // racine : exact (sinon bloquerait tout chemin absolu)
            (PathBuf::from("/System"), true),
            (PathBuf::from("/bin"), true),
            (PathBuf::from("/sbin"), true),
            (PathBuf::from("/usr"), true),
            (PathBuf::from("/Library"), true),
            (PathBuf::from("/Applications"), true),
            (PathBuf::from("/Volumes"), true),
            (PathBuf::from("/Network"), true),
        ];
        if let Ok(home) = std::env::var("HOME") {
            let home = PathBuf::from(home);
            // Arbres entièrement protégés.
            for sub in [
                "Desktop",
                "Documents",
                "Downloads",
                "Pictures",
                "Movies",
                "Music",
                "Library/Keychains",
            ] {
                entries.push((home.join(sub), true));
            }
            for sub in ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"] {
                user_data.push(home.join(sub));
            }
            // Dossiers protégés en exact : on n'efface pas le dossier lui-même, mais ses enfants
            // (un cache applicatif, les données d'une app désinstallée) restent autorisés.
            entries.push((home.clone(), false));
            for sub in [
                "Library",
                "Library/Preferences",
                "Library/Containers",
                "Library/Group Containers",
                "Library/Application Support",
            ] {
                entries.push((home.join(sub), false));
            }
        }
        SafetyContext::with_entries(entries).with_user_data(user_data)
    }

    /// Indique si un chemin est protégé selon ce contexte. Utile à l'UI et aux tests.
    pub fn is_protected_path(&self, path: &Path) -> bool {
        self.is_protected(&path_util::lexical_normalize(path))
    }

    /// Vrai si le chemin est **lui-même** une entrée protégée (quel que soit son mode).
    fn is_protected_entry(&self, normalized: &Path) -> bool {
        self.protected.iter().any(|entry| normalized == entry.path.as_path())
    }

    /// Comme `is_protected`, mais un arbre de documents de l'utilisateur ne protège pas ses
    /// descendants. Toute autre protection (système, Trousseau, entrées exactes) s'applique.
    fn is_protected_beyond_user_data(&self, normalized: &Path) -> bool {
        self.protected.iter().any(|entry| {
            if normalized == entry.path.as_path() {
                return true;
            }
            entry.recursive
                && entry.path.parent().is_some()
                && normalized.starts_with(&entry.path)
                && !self.user_data.contains(&entry.path)
        })
    }

    fn is_protected(&self, normalized: &Path) -> bool {
        self.protected.iter().any(|entry| {
            if normalized == entry.path.as_path() {
                return true;
            }
            // Récursif seulement, et jamais pour la racine du système de fichiers (`/`), sinon
            // `starts_with("/")` serait vrai pour tout chemin absolu.
            entry.recursive && entry.path.parent().is_some() && normalized.starts_with(&entry.path)
        })
    }
}

/// Vrai si `path` lui-même ou l'un de ses ancêtres est un lien symbolique.
///
/// `Ok(true)` = un lien a été trouvé ; `Err` = un statut n'a pas pu être lu (le chemin le plus
/// à droite non lisible). L'appelant traite `Err` comme un refus.
pub(crate) fn symlink_in_path(path: &Path) -> Result<bool, PathBuf> {
    let mut current = Some(path);
    while let Some(p) = current {
        // Racine ou préfixe : plus d'ancêtre à inspecter.
        if p.parent().is_none() {
            break;
        }
        match std::fs::symlink_metadata(p) {
            Ok(md) => {
                if md.file_type().is_symlink() {
                    return Ok(true);
                }
            }
            Err(_) => return Err(p.to_path_buf()),
        }
        current = p.parent();
    }
    Ok(false)
}

/// Vrai si `to` existe sous `from` et qu'aucun composant de `from` (exclu) jusqu'à `to` (inclus)
/// n'est un lien symbolique. Faux à la moindre incertitude.
pub(crate) fn no_symlink_between(from: &Path, to: &Path) -> bool {
    let Ok(rel) = to.strip_prefix(from) else { return false };
    let mut current = from.to_path_buf();
    for comp in rel.components() {
        match comp {
            std::path::Component::Normal(c) => current.push(c),
            _ => return false,
        }
        match std::fs::symlink_metadata(&current) {
            Ok(md) if !md.file_type().is_symlink() => {}
            _ => return false,
        }
    }
    true
}

/// Évalue si `path` peut être retiré, dans l'ordre : anti-symlink, confinement, protection,
/// identité. Toutes les gardes doivent passer. Toute incertitude renvoie un refus.
pub fn evaluate(
    ctx: &SafetyContext,
    path: &Path,
    scope_root: &Path,
    expected: FileIdentity,
) -> Decision {
    // 1. Aucun lien symbolique dans le chemin (fail-closed sur erreur de statut).
    match symlink_in_path(path) {
        Ok(true) => return Decision::Refused(Refusal::SymlinkInPath(path.to_path_buf())),
        Ok(false) => {}
        Err(p) => return Decision::Refused(Refusal::StatError(p)),
    }

    // 2. Confinement sous la racine de la règle (sûr car pas de symlink en ancêtre).
    if !path_util::is_within(path, scope_root) {
        return Decision::Refused(Refusal::OutsideScope {
            path: path.to_path_buf(),
            scope: scope_root.to_path_buf(),
        });
    }

    // 3. Pas dans un arbre protégé (comparaison récursive).
    let normalized = path_util::lexical_normalize(path);
    if ctx.is_protected(&normalized) {
        return Decision::Refused(Refusal::Protected(path.to_path_buf()));
    }

    // 4. Identité inchangée depuis le scan.
    check_identity(path, expected)
}

/// Variante de [`evaluate`] qui re-vérifie aussi que l'élément correspond **toujours** à la règle
/// qui l'a proposé : enfant direct de sa racine (qui sert de périmètre) — ou, si la règle déclare
/// des sous-chemins, exactement `racine/entrée/<sous-chemin>` —, du bon type, retenu par
/// ses prédicats d'inclusion et non écarté par ses exclusions de nom. Une sélection forgée ou
/// périmée (règle modifiée, exclusion ajoutée depuis le scan) est donc refusée.
///
/// C'est aussi le seul moyen d'atteindre un arbre protégé récursivement (ex. `~/Downloads`) :
/// uniquement pour une règle à **liste blanche** (`include` non vide), sur un enfant direct de sa
/// racine, et jamais sur une entrée protégée elle-même. Toutes les autres gardes restent dues.
pub fn evaluate_for_rule(
    ctx: &SafetyContext,
    path: &Path,
    rule: &Rule,
    expected: FileIdentity,
) -> Decision {
    let root = path_util::lexical_normalize(&rule.root_path());
    let normalized = path_util::lexical_normalize(path);

    // 1. Aucun lien symbolique dans le chemin.
    match symlink_in_path(path) {
        Ok(true) => return Decision::Refused(Refusal::SymlinkInPath(path.to_path_buf())),
        Ok(false) => {}
        Err(p) => return Decision::Refused(Refusal::StatError(p)),
    }

    // 2. Confinement strict : `racine/entrée`, ou `racine/entrée/<sous-chemin déclaré>` à
    //    l'identique quand la règle déclare des sous-chemins. Rien d'autre.
    let Ok(rel) = normalized.strip_prefix(&root) else {
        return Decision::Refused(Refusal::OutsideScope { path: path.to_path_buf(), scope: root });
    };
    let mut parts = rel.components();
    let entry = match parts.next() {
        Some(std::path::Component::Normal(name)) => root.join(name),
        _ => return Decision::Refused(Refusal::OutsideScope { path: path.to_path_buf(), scope: root }),
    };
    let rest = parts.as_path();
    let shape_ok = if rule.subpaths.is_empty() {
        rest.as_os_str().is_empty()
    } else {
        rule.subpaths.iter().any(|s| rest == Path::new(s))
    };
    if !shape_ok {
        return Decision::Refused(Refusal::OutsideScope { path: path.to_path_buf(), scope: root });
    }

    // 3. Correspondance à la règle (prédicats bon marché, re-évalués maintenant) : sur l'entrée
    //    (inclusion, exclusions de nom, repère) et sur l'élément lui-même.
    let is_file = std::fs::symlink_metadata(path)
        .map(|md| md.file_type().is_file())
        .unwrap_or(false);
    if (matches!(rule.depth, Depth::Flat) && !is_file)
        || !rule.included(&entry)
        || rule.ignored_by_name(&entry)
        || rule.ignored_by_name(&normalized)
        || !rule.has_marker(&entry)
    {
        return Decision::Refused(Refusal::RuleMismatch(path.to_path_buf()));
    }

    // 4. Protection, avec l'unique dérogation de la liste blanche (enfants directs seulement).
    if ctx.is_protected(&normalized) {
        let whitelisted = !rule.include.is_empty()
            && rule.subpaths.is_empty()
            && !ctx.is_protected_entry(&normalized);
        if !whitelisted {
            return Decision::Refused(Refusal::Protected(path.to_path_buf()));
        }
    }

    // 5. Identité inchangée depuis le scan.
    check_identity(path, expected)
}

fn check_identity(path: &Path, expected: FileIdentity) -> Decision {
    match FileIdentity::of_path(path) {
        Ok(actual) if actual == expected => Decision::Allowed,
        Ok(actual) => Decision::Refused(Refusal::IdentityChanged {
            expected,
            actual: Some(actual),
        }),
        Err(_) => Decision::Refused(Refusal::IdentityChanged {
            expected,
            actual: None,
        }),
    }
}

/// Évalue le retrait d'un **fichier personnel choisi explicitement** par l'utilisateur (module
/// « Gros fichiers »). C'est la seule voie vers un fichier des arbres de documents (Documents,
/// Bureau, Téléchargements…), et elle est volontairement étroite :
///
/// - un **fichier ordinaire** uniquement (jamais un dossier), sans lien symbolique dans le chemin ;
/// - sous `scope_root` (le dossier analysé) ;
/// - toutes les autres protections restent dues (système, Trousseau, dossiers eux-mêmes) ;
/// - identité inchangée depuis l'analyse.
///
/// L'appelant ne doit qu'envoyer à la **corbeille** les éléments autorisés : aucune suppression
/// directe n'est exposée pour ces fichiers.
pub fn evaluate_user_file(
    ctx: &SafetyContext,
    path: &Path,
    scope_root: &Path,
    expected: FileIdentity,
) -> Decision {
    match symlink_in_path(path) {
        Ok(true) => return Decision::Refused(Refusal::SymlinkInPath(path.to_path_buf())),
        Ok(false) => {}
        Err(p) => return Decision::Refused(Refusal::StatError(p)),
    }
    if !path_util::is_within(path, scope_root) {
        return Decision::Refused(Refusal::OutsideScope {
            path: path.to_path_buf(),
            scope: scope_root.to_path_buf(),
        });
    }
    let normalized = path_util::lexical_normalize(path);
    if ctx.is_protected_beyond_user_data(&normalized) {
        return Decision::Refused(Refusal::Protected(path.to_path_buf()));
    }
    match std::fs::symlink_metadata(path) {
        Ok(md) if md.file_type().is_file() => {}
        Ok(_) => return Decision::Refused(Refusal::NotEligible(path.to_path_buf())),
        Err(_) => return Decision::Refused(Refusal::StatError(path.to_path_buf())),
    }
    check_identity(path, expected)
}
