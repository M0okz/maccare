//! Corbeilles : liste fermée, vidage sans suivre les liens, verrous jamais forcés.

use maccare_core::model::FileIdentity;
use maccare_core::trash::{empty_in, locate_in, measure, EmptyRequest};
use maccare_core::walk::{Budget, Control};
use std::ffi::CString;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn uid() -> u32 {
    unsafe { libc::getuid() }
}

fn write(path: &Path, bytes: usize) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, vec![1u8; bytes]).unwrap();
}

fn id(p: &Path) -> FileIdentity {
    FileIdentity::of_path(p).unwrap()
}

/// Demande de vidage pour `bin`, avec l'empreinte du contenu tel qu'il est maintenant affiché.
fn shown(located: &[(PathBuf, String)], bin: &Path) -> EmptyRequest {
    let bins = measure(located, Budget::new(Duration::from_secs(10)), &Control::new());
    let b = bins.iter().find(|b| b.path == bin).expect("corbeille listée");
    EmptyRequest { path: bin.to_path_buf(), identity: b.identity, snapshot: b.snapshot.clone() }
}

/// `home/.Trash` et un volume `vols/Disque/.Trashes/<uid>`.
fn setup() -> (tempfile::TempDir, PathBuf, PathBuf, PathBuf) {
    let (tmp, base) = base();
    let home = base.join("home");
    let vols = base.join("Volumes");
    fs::create_dir_all(home.join(".Trash")).unwrap();
    fs::create_dir_all(vols.join("Disque/.Trashes").join(uid().to_string())).unwrap();
    (tmp, base, home, vols)
}

#[test]
fn locates_only_real_owned_trashes() {
    let (_tmp, base, home, vols) = setup();
    // Disque de démarrage présenté par un lien : ignoré.
    std::os::unix::fs::symlink(&base, vols.join("Macintosh HD")).unwrap();
    // Corbeille de volume qui est un lien : ignorée.
    fs::create_dir_all(vols.join("Piege/.Trashes")).unwrap();
    std::os::unix::fs::symlink(&home, vols.join("Piege/.Trashes").join(uid().to_string())).unwrap();

    let found = locate_in(&home, &vols, uid());
    let labels: Vec<&str> = found.iter().map(|(_, l)| l.as_str()).collect();
    assert_eq!(labels, vec!["Corbeille", "Disque"]);

    // Autre propriétaire (simulé par un autre uid) : rien.
    assert!(locate_in(&home, &vols, uid() + 1).is_empty());

    // ~/.Trash lien symbolique : ignorée.
    let (_t2, base2) = {
        let dir = tempfile::tempdir().unwrap();
        let canonical = dir.path().canonicalize().unwrap();
        (dir, canonical)
    };
    let home2 = base2.join("home");
    fs::create_dir_all(&home2).unwrap();
    fs::create_dir_all(base2.join("ailleurs")).unwrap();
    std::os::unix::fs::symlink(base2.join("ailleurs"), home2.join(".Trash")).unwrap();
    assert!(locate_in(&home2, &base2.join("aucun"), uid()).is_empty());
}

#[test]
fn empties_without_following_links() {
    let (_tmp, base, home, vols) = setup();
    let bin = home.join(".Trash");
    write(&bin.join("vieux.zip"), 50_000);
    write(&bin.join("projet/src/main.rs"), 20_000);
    // Vraies cibles hors corbeille, visées par des liens placés dans la corbeille.
    let outside_file = base.join("garder/precieux.txt");
    let outside_dir = base.join("garder/dossier");
    write(&outside_file, 10_000);
    write(&outside_dir.join("interne.txt"), 10_000);
    std::os::unix::fs::symlink(&outside_file, bin.join("lien-fichier")).unwrap();
    std::os::unix::fs::symlink(&outside_dir, bin.join("lien-dossier")).unwrap();
    // Lien à l'intérieur d'un dossier de la corbeille aussi.
    std::os::unix::fs::symlink(&outside_dir, bin.join("projet/lien-profond")).unwrap();

    let located = locate_in(&home, &vols, uid());
    let results = empty_in(&located, &[shown(&located, &bin)], uid(), &Control::new());
    let r = &results[0];
    assert_eq!(r.refusal, None);
    assert_eq!(r.removed, 4, "{:?}", r.failures);
    assert!(r.failures.is_empty());
    assert!(r.freed_bytes > 0);
    assert_eq!(fs::read_dir(&bin).unwrap().count(), 0, "corbeille vide");
    assert!(bin.is_dir(), "la corbeille elle-même reste");

    // Les cibles des liens sont intactes, contenu compris.
    assert_eq!(fs::read(&outside_file).unwrap().len(), 10_000);
    assert_eq!(fs::read(outside_dir.join("interne.txt")).unwrap().len(), 10_000);
}

#[test]
fn only_the_closed_list_with_matching_identity() {
    let (_tmp, base, home, vols) = setup();
    let bin = home.join(".Trash");
    write(&bin.join("a.bin"), 1_000);
    let docs = base.join("Documents");
    write(&docs.join("rapport.txt"), 1_000);
    let located = locate_in(&home, &vols, uid());

    // Un dossier qui n'est pas une corbeille : refusé, intact.
    let req = |p: &Path, identity: FileIdentity| EmptyRequest { path: p.to_path_buf(), identity, snapshot: shown(&located, &bin).snapshot };
    let r = &empty_in(&located, &[req(&docs, id(&docs))], uid(), &Control::new())[0];
    assert_eq!(r.refusal, Some("not-a-trash"));
    assert!(docs.join("rapport.txt").exists());

    // Un enfant de la corbeille demandé comme corbeille : refusé.
    let sub = bin.join("sous");
    fs::create_dir_all(&sub).unwrap();
    let r = &empty_in(&located, &[req(&sub, id(&sub))], uid(), &Control::new())[0];
    assert_eq!(r.refusal, Some("not-a-trash"));

    // Chemin à normaliser (« .. », double barre) désignant bien la corbeille : admis.
    let odd = PathBuf::from(format!("{}//.Trash/sous/..", home.display()));
    let r = &empty_in(&located, &[req(&odd, id(&bin))], uid(), &Control::new())[0];
    assert_eq!(r.refusal, None);

    // Identité différente de celle affichée : refusé.
    write(&bin.join("b.bin"), 1_000);
    let wrong = FileIdentity { device: id(&bin).device, inode: id(&bin).inode + 1 };
    let r = &empty_in(&located, &[req(&bin, wrong)], uid(), &Control::new())[0];
    assert_eq!(r.refusal, Some("identity-changed"));
    assert!(bin.join("b.bin").exists());

    // Annulé avant de commencer : rien ne part.
    let control = Control::new();
    control.cancel();
    let r = &empty_in(&located, &[shown(&located, &bin)], uid(), &control)[0];
    assert_eq!(r.removed, 0);
    assert!(bin.join("b.bin").exists());
}

#[test]
fn locked_items_are_reported_never_forced() {
    let (_tmp, _base, home, vols) = setup();
    let bin = home.join(".Trash");
    write(&bin.join("verrou.txt"), 1_000);
    write(&bin.join("libre.txt"), 1_000);
    let locked = CString::new(bin.join("verrou.txt").to_str().unwrap()).unwrap();
    assert_eq!(unsafe { libc::chflags(locked.as_ptr(), libc::UF_IMMUTABLE as _) }, 0);

    let located = locate_in(&home, &vols, uid());
    let r = &empty_in(&located, &[shown(&located, &bin)], uid(), &Control::new())[0];
    assert_eq!(r.removed, 1, "le reste part");
    assert_eq!(r.failures.len(), 1);
    assert_eq!(r.failures[0].1, "verrouillé ou protégé");
    assert!(bin.join("verrou.txt").exists(), "jamais forcé");

    // Nettoyage du fichier de test.
    unsafe { libc::chflags(locked.as_ptr(), 0) };
}

#[test]
fn unreadable_trash_is_unknown_not_empty() {
    use std::os::unix::fs::PermissionsExt;
    let (_tmp, _base, home, vols) = setup();
    let bin = home.join(".Trash");
    write(&bin.join("a.bin"), 1_000);
    fs::set_permissions(&bin, fs::Permissions::from_mode(0o000)).unwrap();

    let located = locate_in(&home, &vols, uid());
    let bins = measure(&located, Budget::new(Duration::from_secs(10)), &Control::new());
    fs::set_permissions(&bin, fs::Permissions::from_mode(0o755)).unwrap();

    let home_bin = bins.iter().find(|b| b.label == "Corbeille").unwrap();
    assert!(!home_bin.readable);
    assert!(!home_bin.measured);
}

#[test]
fn content_changed_since_display_refuses_everything() {
    let (_tmp, _base, home, vols) = setup();
    let bin = home.join(".Trash");
    write(&bin.join("ancien.txt"), 1_000);
    let located = locate_in(&home, &vols, uid());
    let displayed = shown(&located, &bin);

    // Après l'affichage, l'utilisateur jette un fichier important : rien ne doit partir.
    write(&bin.join("important.pdf"), 1_000);
    let r = &empty_in(&located, std::slice::from_ref(&displayed), uid(), &Control::new())[0];
    assert_eq!(r.refusal, Some("content-changed"));
    assert_eq!(r.removed, 0);
    assert!(bin.join("important.pdf").exists() && bin.join("ancien.txt").exists());

    // Un élément retiré et un autre ajouté (même nombre) : refusé aussi.
    fs::remove_file(bin.join("important.pdf")).unwrap();
    fs::remove_file(bin.join("ancien.txt")).unwrap();
    write(&bin.join("autre.txt"), 1_000);
    let r = &empty_in(&located, &[displayed], uid(), &Control::new())[0];
    assert_eq!(r.refusal, Some("content-changed"));
    assert!(bin.join("autre.txt").exists());

    // Une empreinte absente est refusée (fail-closed).
    let none = EmptyRequest { path: bin.clone(), identity: id(&bin), snapshot: String::new() };
    assert_eq!(empty_in(&located, &[none], uid(), &Control::new())[0].refusal, Some("content-changed"));

    // .DS_Store réécrit par le Finder entre-temps : pas de faux refus.
    let fresh = shown(&located, &bin);
    write(&bin.join(".DS_Store"), 64);
    let r = &empty_in(&located, &[fresh], uid(), &Control::new())[0];
    assert_eq!(r.refusal, None);
    assert!(!bin.join("autre.txt").exists());
}

/// Un volume monté à l'intérieur de la corbeille n'est jamais touché. Demande `hdiutil`
/// (monter une image disque) : lancer avec `cargo test -- --ignored`.
#[test]
#[ignore]
fn never_crosses_into_a_mounted_volume() {
    use std::process::Command;
    let (_tmp, base, home, vols) = setup();
    let bin = home.join(".Trash");
    let image = base.join("test.dmg");
    let mount = bin.join("monte");
    fs::create_dir_all(&mount).unwrap();
    let ok = Command::new("hdiutil")
        .args(["create", "-size", "10m", "-fs", "APFS", "-volname", "MacCareTest", "-quiet"])
        .arg(&image)
        .status()
        .unwrap()
        .success();
    assert!(ok, "hdiutil create");
    let ok = Command::new("hdiutil")
        .args(["attach", "-nobrowse", "-quiet", "-mountpoint"])
        .arg(&mount)
        .arg(&image)
        .status()
        .unwrap()
        .success();
    assert!(ok, "hdiutil attach");
    fs::write(mount.join("sur-le-volume.txt"), b"ne pas toucher").unwrap();
    write(&bin.join("ordinaire.txt"), 1_000);

    let located = locate_in(&home, &vols, uid());
    let r = empty_in(&located, &[shown(&located, &bin)], uid(), &Control::new()).remove(0);
    let still_there = mount.join("sur-le-volume.txt").exists();
    let _ = Command::new("hdiutil").args(["detach", "-quiet"]).arg(&mount).status();

    assert!(still_there, "le contenu du volume monté est intact");
    assert_eq!(r.removed, 1, "l'élément ordinaire part");
    assert!(r.failures.iter().any(|(p, e)| p.ends_with("monte") && e.contains("autre volume")));
}
