//! Module « Gros fichiers » : recherche, éligibilité, et dérogation étroite de sûreté.

use maccare_core::clean::{execute, execute_for_rule, RemovalMode};
use maccare_core::ffi::{maccare_find_large_files_task, maccare_plan_user_files, maccare_string_free};
use maccare_core::large::{evaluate, find_large_files, is_eligible};
use maccare_core::model::{FileIdentity, ScanItem};
use maccare_core::rules::{Depth, Rule};
use maccare_core::safety::{evaluate as evaluate_scope, evaluate_for_rule, Decision, Refusal, SafetyContext};
use maccare_core::walk::{Budget, Control};
use std::ffi::{CStr, CString};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn write(path: &Path, bytes: usize) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, vec![7u8; bytes]).unwrap();
}

fn id(p: &Path) -> FileIdentity {
    FileIdentity::of_path(p).unwrap()
}

fn budget() -> Budget {
    Budget::new(Duration::from_secs(30))
}

/// Contexte calqué sur la production : `home` protégé exactement, ses dossiers de documents
/// récursivement (et déclarés « documents »), le Trousseau récursivement.
fn context(home: &Path) -> SafetyContext {
    let docs = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"];
    let mut entries: Vec<(PathBuf, bool)> = vec![(home.to_path_buf(), false), (home.join("Library"), false)];
    entries.extend(docs.iter().map(|d| (home.join(d), true)));
    entries.push((home.join("Library/Keychains"), true));
    SafetyContext::with_entries(entries).with_user_data(docs.iter().map(|d| home.join(d)))
}

#[test]
fn finds_largest_files_and_skips_hidden_and_packages() {
    let (_tmp, home) = base();
    write(&home.join("Documents/film.mov"), 3_000_000);
    write(&home.join("Documents/sous/archive.zip"), 2_000_000);
    write(&home.join("Documents/petit.txt"), 1_000);
    write(&home.join(".cache/cache.bin"), 5_000_000);
    write(&home.join("Documents/.cache.bin"), 5_000_000);
    write(&home.join("Photos.photoslibrary/originals/IMG.heic"), 5_000_000);

    let out = find_large_files(&home, 1_000_000, 10, budget(), &Control::new());
    assert!(out.complete);
    assert!(!out.cancelled);
    let names: Vec<_> = out.files.iter().map(|f| f.path.file_name().unwrap().to_string_lossy().into_owned()).collect();
    assert_eq!(names, vec!["film.mov", "archive.zip"], "triés par taille, cachés et paquets exclus");

    // Date de modification lue par le parcours = celle du système.
    let f = &out.files[0];
    assert_eq!(f.modified, fs::metadata(&f.path).unwrap().mtime());
    assert_eq!(f.identity, id(&f.path));
    assert_eq!(f.size_bytes, fs::metadata(&f.path).unwrap().blocks() * 512);

    let limited = find_large_files(&home, 1_000_000, 1, budget(), &Control::new());
    assert_eq!(limited.files.len(), 1);

    let control = Control::new();
    control.cancel();
    let cancelled = find_large_files(&home, 1_000_000, 10, budget(), &control);
    assert!(cancelled.cancelled && cancelled.files.is_empty());
}

#[test]
fn eligibility_is_lexical_and_strict() {
    let root = Path::new("/u/me");
    assert!(is_eligible(Path::new("/u/me/Documents/a.mov"), root));
    assert!(is_eligible(Path::new("/u/me/x.zip"), root));
    assert!(!is_eligible(Path::new("/u/me"), root), "la racine elle-même");
    assert!(!is_eligible(Path::new("/u/other/a.mov"), root), "hors racine");
    assert!(!is_eligible(Path::new("/u/me/.colima/disk.img"), root), "dossier caché");
    assert!(!is_eligible(Path::new("/u/me/Documents/.secret"), root), "fichier caché");
    assert!(!is_eligible(Path::new("/u/me/P.photoslibrary/originals/a.heic"), root), "dans un paquet");
    assert!(!is_eligible(Path::new("/u/me/Documents/../.ssh/id"), root), "normalisé avant contrôle");
    assert!(is_eligible(Path::new("/u/me/Downloads/Outil.pkg"), root), "un fichier-paquet en dernier composant reste proposable");
}

#[test]
fn hidden_home_folders_are_never_eligible_whatever_the_root() {
    // Le contrôle porte sur le chemin depuis HOME, pas seulement depuis la racine fournie.
    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let ssh = home.join(".ssh");
    assert!(!is_eligible(&ssh.join("id_ed25519"), &ssh));
    assert!(!is_eligible(&home.join(".aws/credentials"), &home.join(".aws")));
    let app = home.join("Applications/Exemple.app");
    assert!(!is_eligible(&app.join("Contents/MacOS/Exemple"), &app));
    assert!(is_eligible(&home.join("Documents/film.mov"), &home));

    // Et la validation FFI le refuse aussi, sans lire le disque.
    let input = serde_json::json!({
        "root": home.join(".ssh"),
        "items": [{ "path": home.join(".ssh/id_ed25519"), "identity": { "device": 0, "inode": 0 } }]
    })
    .to_string();
    assert!(unsafe { call(maccare_plan_user_files, &input) }["error"].is_string());
}

#[test]
fn user_file_exception_is_narrow() {
    let (_tmp, home) = base();
    let ctx = context(&home);
    let movie = home.join("Documents/film.mov");
    write(&movie, 10_000);

    // Seule voie autorisée : la sélection explicite d'un fichier ordinaire.
    assert_eq!(evaluate(&ctx, &movie, &home, id(&movie)), Decision::Allowed);

    // Un dossier n'est jamais éligible, ni un dossier de documents lui-même.
    let folder = home.join("Documents/projet");
    fs::create_dir_all(&folder).unwrap();
    assert!(matches!(evaluate(&ctx, &folder, &home, id(&folder)), Decision::Refused(Refusal::NotEligible(_))));
    let docs = home.join("Documents");
    assert!(matches!(evaluate(&ctx, &docs, &home, id(&docs)), Decision::Refused(Refusal::Protected(_))));

    // Le Trousseau reste protégé, même atteint « sous la racine ».
    let kc = home.join("Library/Keychains/login.keychain-db");
    write(&kc, 10_000);
    assert!(matches!(
        maccare_core::safety::evaluate_user_file(&ctx, &kc, &home, id(&kc)),
        Decision::Refused(Refusal::Protected(_))
    ));

    // Identité changée, lien symbolique : refusés.
    let before = id(&movie);
    fs::remove_file(&movie).unwrap();
    write(&movie, 10_000);
    if id(&movie) != before {
        assert!(matches!(evaluate(&ctx, &movie, &home, before), Decision::Refused(Refusal::IdentityChanged { .. })));
    }
    let link = home.join("Documents/lien.mov");
    std::os::unix::fs::symlink(&movie, &link).unwrap();
    assert!(matches!(evaluate(&ctx, &link, &home, id(&link)), Decision::Refused(Refusal::SymlinkInPath(_))));
}

#[test]
fn documents_stay_protected_everywhere_else() {
    let (_tmp, home) = base();
    let ctx = context(&home);
    let movie = home.join("Documents/film.mov");
    write(&movie, 10_000);

    // Garde générale (périmètre) : refus.
    assert!(matches!(evaluate_scope(&ctx, &movie, &home, id(&movie)), Decision::Refused(Refusal::Protected(_))));

    // Garde par règle sans liste blanche : refus.
    let rule = Rule {
        id: "x".into(),
        category: "x".into(),
        version: 1,
        root: home.join("Documents").to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        ..Default::default()
    };
    assert!(matches!(evaluate_for_rule(&ctx, &movie, &rule, id(&movie)), Decision::Refused(Refusal::Protected(_))));

    // Suppression directe, par l'une ou l'autre voie : rien n'est supprimé.
    let items = vec![ScanItem::new(movie.clone(), "c", "r", 0, false, id(&movie))];
    assert!(!execute(&ctx, &home, &items, RemovalMode::DirectDelete)[0].removed);
    assert!(!execute_for_rule(&ctx, &rule, &items, RemovalMode::DirectDelete)[0].removed);
    assert!(movie.exists());
}

unsafe fn call(f: unsafe extern "C" fn(*const i8) -> *mut i8, input: &str) -> serde_json::Value {
    let c = CString::new(input).unwrap();
    let out = f(c.as_ptr());
    let s = CStr::from_ptr(out).to_str().unwrap().to_owned();
    maccare_string_free(out);
    serde_json::from_str(&s).unwrap()
}

unsafe extern "C" fn find(input: *const i8) -> *mut i8 {
    maccare_find_large_files_task(input, std::ptr::null())
}

#[test]
fn ffi_rejects_roots_outside_home_or_in_library() {
    let home = std::env::var("HOME").unwrap();
    for root in [
        "/tmp".to_string(),
        "/".to_string(),
        format!("{home}/Library"),
        format!("{home}/Library/Caches"),
        format!("{home}/.ssh"),
        format!("{home}/.aws"),
        format!("{home}/Documents/.cache"),
        format!("{home}/Applications/Exemple.app"),
        format!("{home}/Documents/../.gnupg"),
    ] {
        let input = serde_json::json!({ "root": root, "items": [] }).to_string();
        assert!(unsafe { call(maccare_plan_user_files, &input) }["error"].is_string(), "{root}");
        let input = serde_json::json!({ "root": root }).to_string();
        assert!(unsafe { call(find, &input) }["error"].is_string(), "{root}");
    }
}
