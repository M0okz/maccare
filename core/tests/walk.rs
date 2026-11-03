//! Mesure parallèle (`walk`) comparée à une référence calculée avec la bibliothèque standard.

use maccare_core::walk::{measure_path, measure_paths, Budget};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn budget() -> Budget {
    Budget::new(Duration::from_secs(30))
}

/// Référence : somme des blocs alloués, sans suivre les liens, liens physiques dédoublonnés.
/// Itérative, pour ne pas dépendre de la pile du thread de test sur une arborescence profonde.
fn reference(path: &Path, seen: &mut std::collections::HashSet<(u64, u64)>) -> u64 {
    let mut total = 0;
    let mut stack = vec![path.to_path_buf()];
    while let Some(p) = stack.pop() {
        let md = fs::symlink_metadata(&p).unwrap();
        if md.file_type().is_file() {
            if md.nlink() <= 1 || seen.insert((md.dev(), md.ino())) {
                total += md.blocks() * 512;
            }
        } else if md.is_dir() {
            stack.extend(fs::read_dir(&p).unwrap().flatten().map(|e| e.path()));
        }
    }
    total
}

#[test]
fn matches_reference_on_large_tree() {
    let (_tmp, base) = base();
    // Assez d'entrées dans un même dossier pour exiger plusieurs appels getattrlistbulk.
    let wide = base.join("wide");
    fs::create_dir_all(&wide).unwrap();
    for i in 0..3000 {
        fs::write(wide.join(format!("fichier-au-nom-plutot-long-{i:05}.bin")), vec![b'x'; i % 9000]).unwrap();
    }
    // Et de la profondeur.
    let mut deep = base.join("deep");
    for i in 0..150 {
        deep = deep.join(format!("d{i}"));
    }
    fs::create_dir_all(&deep).unwrap();
    fs::write(deep.join("fond.bin"), vec![0u8; 50_000]).unwrap();

    let m = measure_path(&base, budget());
    assert!(m.complete);
    assert_eq!(m.bytes, reference(&base, &mut Default::default()));
    assert!(m.bytes > 3000 * 4096 / 2, "les fichiers sont bien comptés");
}

#[test]
fn counts_hard_links_once_and_never_follows_symlinks() {
    let (_tmp, base) = base();
    let outside = base.join("outside");
    fs::create_dir_all(&outside).unwrap();
    fs::write(outside.join("big.bin"), vec![1u8; 200_000]).unwrap();

    let root = base.join("root");
    fs::create_dir_all(root.join("a")).unwrap();
    fs::create_dir_all(root.join("b")).unwrap();
    fs::write(root.join("a/data.bin"), vec![2u8; 100_000]).unwrap();
    fs::hard_link(root.join("a/data.bin"), root.join("b/data-link.bin")).unwrap();
    std::os::unix::fs::symlink(&outside, root.join("vers-dehors")).unwrap();

    let once = fs::symlink_metadata(root.join("a/data.bin")).unwrap().blocks() * 512;
    let m = measure_path(&root, budget());
    assert!(m.complete);
    assert_eq!(m.bytes, once, "lien physique compté une fois, lien symbolique non suivi");
}

#[test]
fn results_follow_input_order_and_tolerate_missing_paths() {
    let (_tmp, base) = base();
    fs::create_dir_all(base.join("x")).unwrap();
    fs::write(base.join("x/f"), vec![0u8; 10_000]).unwrap();
    fs::write(base.join("seul.bin"), vec![0u8; 20_000]).unwrap();

    let roots = vec![base.join("absent"), base.join("x"), base.join("seul.bin")];
    let out = measure_paths(&roots, budget());
    assert_eq!(out.len(), 3);
    assert_eq!(out[0].bytes, 0);
    assert!(out[0].complete);
    assert_eq!(out[1].bytes, reference(&base.join("x"), &mut Default::default()));
    assert_eq!(out[2].bytes, fs::metadata(base.join("seul.bin")).unwrap().blocks() * 512);
}

#[test]
fn unreadable_directory_counts_zero_without_blocking() {
    use std::os::unix::fs::PermissionsExt;

    let (_tmp, base) = base();
    let locked = base.join("verrou");
    fs::create_dir_all(locked.join("dedans")).unwrap();
    fs::write(locked.join("dedans/f"), vec![0u8; 10_000]).unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o000)).unwrap();

    let start = Instant::now();
    let m = measure_path(&locked, budget());
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();

    assert!(start.elapsed() < Duration::from_secs(2));
    assert!(m.complete);
    assert_eq!(m.bytes, 0);
}

#[test]
fn zero_budget_returns_immediately() {
    let (_tmp, base) = base();
    fs::create_dir_all(base.join("d")).unwrap();
    fs::write(base.join("d/f"), b"x").unwrap();

    let start = Instant::now();
    let m = measure_path(&base, Budget::new(Duration::ZERO));
    assert!(start.elapsed() < Duration::from_secs(1));
    // Les workers peuvent avoir fini avant l'attente : seul compte qu'on rende la main tout de
    // suite, avec une taille jamais surestimée.
    assert!(m.bytes <= reference(&base, &mut Default::default()));
}
