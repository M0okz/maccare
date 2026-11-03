//! Intégration scan → clean sur une arborescence temporaire jetable.

use maccare_core::clean::{execute, RemovalMode};
use maccare_core::rules::{Depth, Rule};
use maccare_core::safety::SafetyContext;
use maccare_core::scan::scan_rule;
use std::fs;
use std::path::PathBuf;

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

/// Espace alloué d'un fichier, tel que le rapporte le système (référence des mesures).
fn allocated(path: &PathBuf) -> u64 {
    use std::os::unix::fs::MetadataExt;
    fs::symlink_metadata(path).unwrap().blocks() * 512
}

#[test]
fn scans_applies_exclusions_then_cleans() {
    let (_tmp, base) = base();
    let caches = base.join("Caches");

    write_file(&caches.join("app1/blob.bin"), "aaaa");
    write_file(&caches.join("app2/blob.bin"), "bbbb");
    write_file(&caches.join(".DS_Store"), "x");
    write_file(&caches.join("com.apple.test/blob.bin"), "cccc");

    let rule = Rule {
        id: "cache.generic".into(),
        category: "user-cache".into(),
        version: 1,
        root: caches.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        autoselect: false,
        exclude: vec![
            maccare_core::rules::Exclude::Name {
                equals: ".DS_Store".into(),
            },
            maccare_core::rules::Exclude::PathPrefix {
                value: caches.join("com.apple.test").to_string_lossy().into_owned(),
            },
        ],
        ..Default::default()
    };

    let outcome = scan_rule(&rule);
    let names: Vec<String> = outcome
        .items
        .iter()
        .map(|i| i.path.file_name().unwrap().to_string_lossy().into_owned())
        .collect();

    assert!(names.contains(&"app1".to_string()));
    assert!(names.contains(&"app2".to_string()));
    assert!(!names.contains(&".DS_Store".to_string()), "exclusion par nom");
    assert!(
        !names.contains(&"com.apple.test".to_string()),
        "exclusion par préfixe de chemin"
    );

    // Nettoyage réel sous périmètre, sans racine protégée particulière.
    let ctx = SafetyContext::new([]);
    let results = execute(&ctx, &caches, &outcome.items, RemovalMode::DirectDelete);

    assert!(results.iter().all(|r| r.decision.is_allowed()));
    assert!(results.iter().all(|r| r.removed));
    assert!(!caches.join("app1").exists());
    assert!(!caches.join("app2").exists());
    // Les éléments exclus n'ont jamais été candidats, donc toujours présents.
    assert!(caches.join(".DS_Store").exists());
    assert!(caches.join("com.apple.test").exists());
}

#[test]
fn dry_run_does_not_delete() {
    let (_tmp, base) = base();
    let caches = base.join("Caches");
    write_file(&caches.join("app1/blob.bin"), "aaaa");

    let rule = Rule {
        id: "cache.generic".into(),
        category: "user-cache".into(),
        version: 1,
        root: caches.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        autoselect: false,
        exclude: vec![],
        ..Default::default()
    };

    let outcome = scan_rule(&rule);
    let ctx = SafetyContext::new([]);
    let results = execute(&ctx, &caches, &outcome.items, RemovalMode::DryRun);

    assert!(results.iter().all(|r| r.decision.is_allowed()));
    assert!(results.iter().all(|r| !r.removed));
    assert!(caches.join("app1").exists(), "le dry-run ne supprime rien");
}

#[test]
fn name_prefix_excludes_before_sizing() {
    // Un dossier `com.apple.*` doit être écarté par le préfixe de nom et ne jamais figurer
    // dans les résultats, qu'il contienne des données ou non.
    let (_tmp, base) = base();
    let caches = base.join("Caches");
    write_file(&caches.join("app1/blob.bin"), "aaaa");
    write_file(&caches.join("com.apple.Safari/data.bin"), "secret");

    let rule = Rule {
        id: "cache.generic".into(),
        category: "user-cache".into(),
        version: 1,
        root: caches.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        autoselect: false,
        exclude: vec![maccare_core::rules::Exclude::NamePrefix {
            starts_with: "com.apple.".into(),
        }],
        ..Default::default()
    };

    let outcome = scan_rule(&rule);
    let names: Vec<String> = outcome
        .items
        .iter()
        .map(|i| i.path.file_name().unwrap().to_string_lossy().into_owned())
        .collect();

    assert!(names.contains(&"app1".to_string()));
    assert!(
        !names.contains(&"com.apple.Safari".to_string()),
        "les caches Apple sont écartés par le préfixe de nom"
    );
}

#[test]
fn measure_children_sorts_by_size_and_flags_dirs() {
    use maccare_core::scan::{measure_children, MEASURE_DEFAULT_BUDGET};

    let (_tmp, base) = base();
    // Tailles comptées en espace alloué sur disque (comme `du`) : big/ = deux fichiers, plus
    // gros que small.txt quelle que soit la taille de bloc du volume.
    write_file(&base.join("big/a.bin"), "aaaa");
    write_file(&base.join("big/b.bin"), "bbbb");
    write_file(&base.join("small.txt"), "ab");

    let outcome = measure_children(&base, MEASURE_DEFAULT_BUDGET);
    assert_eq!(outcome.children.len(), 2);

    // Trié par taille décroissante : le dossier "big" (8 o) avant "small.txt" (2 o).
    let first = &outcome.children[0];
    assert_eq!(first.path.file_name().unwrap(), "big");
    assert!(first.is_dir);
    assert!(first.measured);
    assert_eq!(first.size_bytes, allocated(&base.join("big/a.bin")) + allocated(&base.join("big/b.bin")));

    let second = &outcome.children[1];
    assert_eq!(second.path.file_name().unwrap(), "small.txt");
    assert!(!second.is_dir);
    assert_eq!(second.size_bytes, allocated(&base.join("small.txt")));
}

#[test]
fn include_suffix_limits_scan_candidates() {
    use maccare_core::rules::Include;

    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    write_file(&downloads.join("app.dmg"), "aaaa");
    write_file(&downloads.join("tool.pkg"), "bbbb");
    write_file(&downloads.join("notes.txt"), "cccc");
    write_file(&downloads.join("Archive.DMG"), "dddd");

    let rule = Rule {
        id: "downloads.installers".into(),
        category: "downloads-installers".into(),
        version: 1,
        root: downloads.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        include: vec![
            Include::NameSuffix { ends_with: ".dmg".into() },
            Include::NameSuffix { ends_with: ".pkg".into() },
        ],
        ..Default::default()
    };

    let mut names: Vec<String> = scan_rule(&rule)
        .items
        .iter()
        .map(|i| i.path.file_name().unwrap().to_string_lossy().into_owned())
        .collect();
    names.sort();

    assert_eq!(names, vec!["Archive.DMG", "app.dmg", "tool.pkg"]);
    assert!(!names.contains(&"notes.txt".to_string()), "hors inclusion : écarté");
}
