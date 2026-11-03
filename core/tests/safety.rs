//! Cas négatifs de sûreté — ils doivent tous **refuser**.
//!
//! Propriété vérifiée : aucun chemin hors périmètre, protégé, d'identité modifiée, ou dont le
//! statut est illisible, n'est jamais autorisé à la suppression.

use maccare_core::model::FileIdentity;
use maccare_core::safety::{evaluate, Decision, Refusal, SafetyContext};
use std::fs;
use std::os::unix::fs as unixfs;
use std::path::{Path, PathBuf};

/// Racine de test canonicalisée : résout `/var -> /private/var` sur macOS pour qu'aucun
/// ancêtre ne soit un lien symbolique (ce qui est le cas des vrais chemins `~/Library/...`).
fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn write_file(path: &PathBuf, contents: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, contents).unwrap();
}

#[test]
fn allows_normal_file_in_scope() {
    let (_tmp, base) = base();
    let file = base.join("cache/app1/data.bin");
    write_file(&file, "payload");
    let id = FileIdentity::of_path(&file).unwrap();
    let ctx = SafetyContext::new([]);

    assert_eq!(evaluate(&ctx, &file, &base, id), Decision::Allowed);
}

#[test]
fn refuses_protected_tree_recursively() {
    let (_tmp, base) = base();
    let protected_root = base.join("Library/Keychains");
    let victim = protected_root.join("deep/inner/secret");
    write_file(&victim, "x");
    let id = FileIdentity::of_path(&victim).unwrap();
    let ctx = SafetyContext::new([protected_root.clone()]);

    match evaluate(&ctx, &victim, &base, id) {
        Decision::Refused(Refusal::Protected(_)) => {}
        other => panic!("attendu Protected, obtenu {other:?}"),
    }
}

#[test]
fn refuses_symlink_ancestor() {
    let (_tmp, base) = base();
    let real_dir = base.join("real");
    let real_file = real_dir.join("data.bin");
    write_file(&real_file, "payload");
    let link_dir = base.join("link");
    unixfs::symlink(&real_dir, &link_dir).unwrap();

    // Identité capturée sur le vrai fichier...
    let id = FileIdentity::of_path(&real_file).unwrap();
    // ...mais le chemin demandé passe par le lien.
    let via_link = link_dir.join("data.bin");
    let ctx = SafetyContext::new([]);

    match evaluate(&ctx, &via_link, &base, id) {
        Decision::Refused(Refusal::SymlinkInPath(_)) => {}
        other => panic!("attendu SymlinkInPath, obtenu {other:?}"),
    }
}

#[test]
fn refuses_outside_scope() {
    let (_tmp, base) = base();
    let scope = base.join("scope");
    let outside = base.join("other/data.bin");
    write_file(&outside, "payload");
    let id = FileIdentity::of_path(&outside).unwrap();
    let ctx = SafetyContext::new([]);

    match evaluate(&ctx, &outside, &scope, id) {
        Decision::Refused(Refusal::OutsideScope { .. }) => {}
        other => panic!("attendu OutsideScope, obtenu {other:?}"),
    }
}

#[test]
fn refuses_identity_changed_since_scan() {
    let (_tmp, base) = base();
    let file = base.join("cache/data.bin");
    write_file(&file, "original");
    let id = FileIdentity::of_path(&file).unwrap();

    // Le fichier scanné est remplacé par un autre au même chemin (nouvel inode).
    fs::remove_file(&file).unwrap();
    write_file(&file, "remplacant different");
    let ctx = SafetyContext::new([]);

    match evaluate(&ctx, &file, &base, id) {
        Decision::Refused(Refusal::IdentityChanged { .. }) => {}
        other => panic!("attendu IdentityChanged, obtenu {other:?}"),
    }
}

#[test]
fn root_is_protected_only_exactly_not_recursively() {
    // Régression : "/" ne doit pas protéger tout chemin absolu via starts_with.
    let ctx = SafetyContext::new([PathBuf::from("/")]);
    let (_tmp, base) = base();
    let file = base.join("cache/data.bin");
    write_file(&file, "payload");
    let id = FileIdentity::of_path(&file).unwrap();

    // Un chemin arbitraire sous "/" n'est pas protégé par la seule présence de "/".
    assert_eq!(evaluate(&ctx, &file, &base, id), Decision::Allowed);
}

#[test]
fn default_env_protection_is_exact_or_recursive_as_expected() {
    let home = match std::env::var("HOME") {
        Ok(h) => PathBuf::from(h),
        Err(_) => return, // pas de HOME : rien à vérifier
    };
    let ctx = SafetyContext::default_for_env();

    // Exact : le dossier lui-même protégé, ses enfants autorisés.
    assert!(ctx.is_protected_path(&home), "le home est protégé");
    assert!(ctx.is_protected_path(&home.join("Library")), "~/Library protégé");
    assert!(ctx.is_protected_path(&home.join("Library/Containers")));
    assert!(
        !ctx.is_protected_path(&home.join("Library/Caches/com.app.one")),
        "régression: un cache sous ~ ne doit pas être protégé"
    );
    assert!(
        !ctx.is_protected_path(&home.join("Library/Containers/com.app.one")),
        "un enfant de Containers reste désinstallable"
    );

    // Récursif : tout l'arbre protégé.
    assert!(ctx.is_protected_path(&home.join("Library/Keychains/login.keychain-db")));
    assert!(ctx.is_protected_path(&home.join("Documents/rapport.txt")));
    assert!(ctx.is_protected_path(Path::new("/System/Library/x")));
}

#[test]
fn refuses_missing_leaf_fail_closed() {
    let (_tmp, base) = base();
    let ghost = base.join("cache/does-not-exist");
    let fake_id = FileIdentity {
        device: 1,
        inode: 1,
    };
    let ctx = SafetyContext::new([]);

    match evaluate(&ctx, &ghost, &base, fake_id) {
        Decision::Refused(Refusal::StatError(_)) => {}
        other => panic!("attendu StatError, obtenu {other:?}"),
    }
}
