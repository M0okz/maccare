//! Module « Doublons » : recherche en trois passes et validation qui garantit qu'une copie reste.

use maccare_core::dupes::{evaluate_group, evaluate_groups, find_duplicates, Candidate, PlanGroup};
use maccare_core::ffi::{maccare_find_duplicates_task, maccare_plan_duplicates, maccare_string_free};
use maccare_core::model::FileIdentity;
use maccare_core::safety::{Decision, Refusal, SafetyContext};
use maccare_core::walk::{Budget, Control};
use std::ffi::{CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn write(path: &Path, data: &[u8]) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, data).unwrap();
}

/// Contenu pseudo-aléatoire déterministe.
fn content(seed: u8, len: usize) -> Vec<u8> {
    (0..len).map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed)).collect()
}

fn cand(p: &Path) -> Candidate {
    Candidate { path: p.to_path_buf(), identity: FileIdentity::of_path(p).unwrap() }
}

fn ctx(home: &Path) -> SafetyContext {
    let docs = ["Documents", "Downloads", "Desktop"];
    let mut entries: Vec<(PathBuf, bool)> = vec![(home.to_path_buf(), false)];
    entries.extend(docs.iter().map(|d| (home.join(d), true)));
    SafetyContext::with_entries(entries).with_user_data(docs.iter().map(|d| home.join(d)))
}

fn budget() -> Budget {
    Budget::new(Duration::from_secs(30))
}

fn names(files: &[maccare_core::dupes::DupFile]) -> Vec<String> {
    let mut v: Vec<_> = files.iter().map(|f| f.path.file_name().unwrap().to_string_lossy().into_owned()).collect();
    v.sort();
    v
}

#[test]
fn finds_only_true_duplicates() {
    let (_tmp, home) = base();
    let big = content(1, 300_000);
    write(&home.join("Documents/a.bin"), &big);
    write(&home.join("Downloads/a-copie.bin"), &big);
    write(&home.join("Desktop/a (2).bin"), &big);

    // Même taille, même tête et même queue, milieu différent : séparé à la troisième passe.
    let mut near = big.clone();
    near[150_000] ^= 0xFF;
    write(&home.join("Documents/presque.bin"), &near);

    // Même taille, contenu différent.
    write(&home.join("Documents/autre.bin"), &content(9, 300_000));

    // Lien physique : pas une copie.
    let solo = content(3, 200_000);
    write(&home.join("Documents/solo.bin"), &solo);
    fs::hard_link(home.join("Documents/solo.bin"), home.join("Downloads/solo-lien.bin")).unwrap();

    // Copie dans un dossier caché : hors périmètre.
    write(&home.join(".cache/a.bin"), &big);

    // Copies dans des projets de code : ignorées (dépôt git, artefacts Rust, dépendances npm).
    write(&home.join("Documents/projet/.git/HEAD"), b"ref");
    write(&home.join("Documents/projet/src/a.bin"), &big);
    write(&home.join("Documents/outil/target/CACHEDIR.TAG"), b"Signature");
    write(&home.join("Documents/outil/target/debug/a.bin"), &big);
    write(&home.join("Documents/site/node_modules/pkg/a.bin"), &big);

    // Petit doublon (contenu entier lu dès la deuxième passe).
    write(&home.join("Documents/petit.txt"), b"bonjour");
    write(&home.join("Downloads/petit.txt"), b"bonjour");

    let out = find_duplicates(&home, 1, budget(), &Control::new());
    assert!(out.complete && !out.cancelled);
    assert_eq!(out.groups.len(), 2, "{:?}", out.groups);
    assert_eq!(names(&out.groups[0].files), vec!["a (2).bin", "a-copie.bin", "a.bin"]);
    assert!(out.groups[0].reclaimable() > 0);
    assert_eq!(names(&out.groups[1].files), vec!["petit.txt", "petit.txt"]);

    let control = Control::new();
    control.cancel();
    let cancelled = find_duplicates(&home, 1, budget(), &control);
    assert!(cancelled.cancelled && cancelled.groups.is_empty());
}

#[test]
fn removal_requires_a_present_identical_kept_copy() {
    let (_tmp, home) = base();
    let data = content(5, 100_000);
    let (a, b, c) = (home.join("Documents/a.bin"), home.join("Documents/b.bin"), home.join("Downloads/c.bin"));
    for p in [&a, &b, &c] {
        write(p, &data);
    }
    let ctx = ctx(&home);

    // Cas normal : on garde a, on retire b et c.
    let d = evaluate_group(&ctx, &home, &cand(&a), &[cand(&b), cand(&c)]);
    assert!(d.iter().all(Decision::is_allowed), "{d:?}");

    // Tout sélectionner (l'exemplaire conservé figure aussi dans les retraits) : tout est refusé.
    let d = evaluate_group(&ctx, &home, &cand(&a), &[cand(&a), cand(&b), cand(&c)]);
    assert!(d.iter().all(|x| matches!(x, Decision::Refused(Refusal::NoKeptCopy(_)))));

    // Exemplaire conservé disparu ou remplacé : tout est refusé.
    let gone = cand(&c);
    fs::remove_file(&c).unwrap();
    let d = evaluate_group(&ctx, &home, &gone, &[cand(&a)]);
    assert!(matches!(d[0], Decision::Refused(Refusal::NoKeptCopy(_))));
    write(&c, &data);

    // Fichier modifié depuis l'analyse (même inode) : n'est plus un doublon.
    let before = cand(&b);
    let mut changed = data.clone();
    changed[42] ^= 1;
    fs::write(&b, &changed).unwrap();
    let d = evaluate_group(&ctx, &home, &cand(&a), &[before]);
    assert!(matches!(d[0], Decision::Refused(Refusal::NotDuplicate(_))), "{d:?}");

    // Groupe forgé : même taille, contenu différent.
    let other = home.join("Documents/autre.bin");
    write(&other, &content(6, 100_000));
    let d = evaluate_group(&ctx, &home, &cand(&a), &[cand(&other)]);
    assert!(matches!(d[0], Decision::Refused(Refusal::NotDuplicate(_))));

    // Lien physique vers l'exemplaire conservé : même fichier, refusé.
    let link = home.join("Downloads/a-lien.bin");
    fs::hard_link(&a, &link).unwrap();
    let d = evaluate_group(&ctx, &home, &cand(&a), &[cand(&link)]);
    assert!(matches!(d[0], Decision::Refused(Refusal::NoKeptCopy(_))));

    // Exemplaire conservé caché (ex. dans une corbeille) : ne compte pas comme copie.
    let hidden = home.join(".Trash/a.bin");
    write(&hidden, &data);
    let d = evaluate_group(&ctx, &home, &cand(&hidden), &[cand(&a)]);
    assert!(matches!(d[0], Decision::Refused(Refusal::NoKeptCopy(_))));
}

#[test]
fn crossed_groups_cannot_remove_every_copy() {
    let (_tmp, home) = base();
    let data = content(7, 50_000);
    let (x, y) = (home.join("Documents/x.bin"), home.join("Downloads/y.bin"));
    write(&x, &data);
    write(&y, &data);
    let ctx = ctx(&home);

    let groups = vec![
        PlanGroup { keep: cand(&x), remove: vec![cand(&y)] },
        PlanGroup { keep: cand(&y), remove: vec![cand(&x)] },
    ];
    let d = evaluate_groups(&ctx, &home, &groups);
    assert_eq!(d.len(), 2);
    assert!(d.iter().all(|(_, d)| matches!(d, Decision::Refused(Refusal::NoKeptCopy(_)))));
}

unsafe fn call(f: unsafe extern "C" fn(*const i8) -> *mut i8, input: &str) -> serde_json::Value {
    let c = CString::new(input).unwrap();
    let out = f(c.as_ptr());
    let s = CStr::from_ptr(out).to_str().unwrap().to_owned();
    maccare_string_free(out);
    serde_json::from_str(&s).unwrap()
}

unsafe extern "C" fn find(input: *const i8) -> *mut i8 {
    maccare_find_duplicates_task(input, std::ptr::null())
}

#[test]
fn ffi_rejects_roots_outside_home_hidden_or_in_library() {
    let home = std::env::var("HOME").unwrap();
    for root in ["/tmp".to_string(), format!("{home}/Library"), format!("{home}/.ssh")] {
        let input = serde_json::json!({ "root": root }).to_string();
        assert!(unsafe { call(find, &input) }["error"].is_string(), "{root}");
        let input = serde_json::json!({ "root": root, "groups": [] }).to_string();
        assert!(unsafe { call(maccare_plan_duplicates, &input) }["error"].is_string(), "{root}");
    }
}
