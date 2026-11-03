//! Règles système fermées (assistant privilégié), testées **sans privilèges** sur des dossiers de
//! test. Les règles réelles ne sont jamais utilisées pour supprimer ici.

use maccare_core::model::FileIdentity;
use maccare_core::system::{list, remove, Limits, SystemRule, SystemRuleId};
use std::ffi::CString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

/// Propriétaire admis dans les tests : l'utilisateur courant (les vraies règles : système seulement).
fn me(uid: u32) -> bool {
    uid == unsafe { libc::getuid() }
}

/// Racine de test dans un dossier temporaire **propre au test** : son parent sert aux éléments
/// « hors racine » sans collision entre tests.
fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().canonicalize().unwrap().join("racine");
    fs::create_dir_all(&root).unwrap();
    (dir, root)
}

fn write(path: &Path, bytes: usize, days_old: u64) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, vec![1u8; bytes]).unwrap();
    let f = fs::File::options().write(true).open(path).unwrap();
    f.set_modified(SystemTime::now() - Duration::from_secs(days_old * 86_400)).unwrap();
}

fn names(rule: &SystemRule) -> Vec<String> {
    let mut v: Vec<String> = list(rule, Limits::default()).unwrap().items.into_iter().map(|i| i.rel_path).collect();
    v.sort();
    v
}

fn id(p: &Path) -> FileIdentity {
    FileIdentity::of_path(p).unwrap()
}

#[test]
fn rule_ids_are_a_closed_list() {
    for r in SystemRuleId::ALL {
        assert_eq!(SystemRuleId::parse(r.as_str()), Some(r));
    }
    for bad in ["", "sys.caches.third-party", "/Library/Logs", "sys.logs.library/../.."] {
        assert_eq!(SystemRuleId::parse(bad), None, "{bad}");
    }
    assert_eq!(SystemRuleId::LogsRotated.rule().root, PathBuf::from("/private/var/log"));
}

#[test]
fn library_logs_lists_old_files_only_and_skips_unsafe_things() {
    let (_tmp, root) = base();
    write(&root.join("App/vieux.log"), 5_000, 40);
    write(&root.join("App/recent.log"), 5_000, 2);
    write(&root.join("DiagnosticReports/crash.ips"), 5_000, 40); // règle à part
    write(&root.join("installer.log"), 5_000, 90);
    // Lien vers un fichier hors racine, et lien vers un dossier : jamais suivis.
    write(&root.parent().unwrap().join("dehors/secret.log"), 5_000, 90);
    std::os::unix::fs::symlink(root.parent().unwrap().join("dehors/secret.log"), root.join("lien.log")).unwrap();
    std::os::unix::fs::symlink(root.parent().unwrap().join("dehors"), root.join("lien-dossier")).unwrap();
    // Dossier inscriptible par tous : refusé.
    write(&root.join("Partage/vieux.log"), 5_000, 90);
    fs::set_permissions(root.join("Partage"), fs::Permissions::from_mode(0o777)).unwrap();
    // Fichier verrouillé : signalé, jamais proposé.
    write(&root.join("verrou.log"), 5_000, 90);
    let locked = CString::new(root.join("verrou.log").to_str().unwrap()).unwrap();
    assert_eq!(unsafe { libc::chflags(locked.as_ptr(), libc::UF_IMMUTABLE as _) }, 0);

    let rule = SystemRule::at(SystemRuleId::LogsLibrary, root.clone(), me);
    let listing = list(&rule, Limits::default()).unwrap();
    let mut got: Vec<_> = listing.items.iter().map(|i| i.rel_path.clone()).collect();
    got.sort();
    assert_eq!(got, vec!["App/vieux.log", "installer.log"]);
    let skipped: Vec<_> = listing.skipped.iter().map(|(p, w)| format!("{p}:{w}")).collect();
    assert!(skipped.contains(&"lien.log:lien".to_string()), "{skipped:?}");
    assert!(skipped.contains(&"lien-dossier:lien".to_string()));
    assert!(skipped.contains(&"Partage:dossier non sûr".to_string()));
    assert!(skipped.contains(&"verrou.log:verrouillé".to_string()));

    unsafe { libc::chflags(locked.as_ptr(), 0) };
    fs::set_permissions(root.join("Partage"), fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn rotated_rule_takes_closed_archives_only() {
    let (_tmp, root) = base();
    for n in ["system.log.0.gz", "wifi.log.3.bz2", "keybagd.log.0", "install.log.12", "x.xz"] {
        write(&root.join(n), 2_000, 3);
    }
    for n in ["system.log", "wifi.log", "notes", "archive.gz.tmp", ".5"] {
        write(&root.join(n), 2_000, 3);
    }
    write(&root.join("today.log.1.gz"), 2_000, 0); // trop récente
    write(&root.join("com.apple.xpc.launchd/launchd.log.1"), 2_000, 3);
    let rule = SystemRule::at(SystemRuleId::LogsRotated, root, me);
    assert_eq!(
        names(&rule),
        vec!["com.apple.xpc.launchd/launchd.log.1", "install.log.12", "keybagd.log.0", "system.log.0.gz", "wifi.log.3.bz2", "x.xz"]
    );
}

#[test]
fn removes_only_listed_identities_that_still_match() {
    let (_tmp, root) = base();
    let a = root.join("a.log");
    let b = root.join("b.log");
    let keep = root.join("garder.log");
    for p in [&a, &b, &keep] {
        write(p, 8_000, 40);
    }
    let outside = root.parent().unwrap().join("dehors-precieux.log");
    write(&outside, 8_000, 40);
    let rule = SystemRule::at(SystemRuleId::LogsLibrary, root.clone(), me);
    let (ida, idb) = (id(&a), id(&b));

    // b est remplacé par un lien vers un fichier hors racine après la liste.
    fs::remove_file(&b).unwrap();
    std::os::unix::fs::symlink(&outside, &b).unwrap();

    let unknown = FileIdentity { device: ida.device, inode: 1 };
    let r = remove(&rule, &[ida, idb, unknown], Limits::default()).unwrap();
    assert_eq!(r.removed, 1);
    assert!(r.freed_bytes > 0);
    assert!(!a.exists(), "a supprimé");
    assert!(keep.exists(), "jamais désigné : intact");
    assert!(fs::symlink_metadata(&b).unwrap().file_type().is_symlink(), "le lien n'est pas touché");
    assert!(outside.exists(), "la cible hors racine est intacte");
    assert_eq!(r.not_found, 2, "b (devenu lien) et l'identité inconnue ne sont pas trouvés");
}

#[test]
fn refuses_hard_links_recent_files_and_changed_content() {
    let (_tmp, root) = base();
    let linked = root.join("lie.log");
    write(&linked, 4_000, 40);
    fs::hard_link(&linked, root.join("autre-nom.log")).unwrap();
    let recent = root.join("recent.log");
    write(&recent, 4_000, 1);
    let rule = SystemRule::at(SystemRuleId::LogsLibrary, root.clone(), me);
    let r = remove(&rule, &[id(&linked), id(&recent)], Limits::default()).unwrap();
    assert_eq!(r.removed, 0);
    assert!(linked.exists() && recent.exists());
    let reasons: Vec<_> = r.refused.iter().map(|(_, w)| *w).collect();
    assert!(reasons.contains(&"liens multiples") && reasons.contains(&"trop récent"), "{reasons:?}");
}

#[test]
fn limits_bound_the_work() {
    let (_tmp, root) = base();
    for i in 0..20 {
        write(&root.join(format!("f{i}.log")), 1_000, 40);
    }
    let rule = SystemRule::at(SystemRuleId::LogsLibrary, root, me);
    let l = list(&rule, Limits { max_items: 5, max_duration: Duration::from_secs(30) }).unwrap();
    assert_eq!(l.items.len(), 5);
    assert!(l.truncated);
}

#[test]
fn foreign_owner_and_unsafe_root_are_refused() {
    let (_tmp, root) = base();
    write(&root.join("vieux.log"), 1_000, 40);
    // Propriétaires admis = système seulement (comme en vrai) : la racine de test est refusée.
    let strict = SystemRule::at(SystemRuleId::LogsLibrary, root.clone(), maccare_core::system::is_system_id);
    assert!(list(&strict, Limits::default()).is_err());
    // Racine qui passe par un lien : refusée.
    let link = root.parent().unwrap().join("racine-lien");
    std::os::unix::fs::symlink(&root, &link).unwrap();
    let via_link = SystemRule::at(SystemRuleId::LogsLibrary, link, me);
    assert!(list(&via_link, Limits::default()).is_err());
}

#[test]
fn real_rules_can_be_listed_read_only() {
    // Lecture seule des vraies règles, sans privilèges : jamais de suppression dans un test.
    if let Ok(l) = list(&SystemRuleId::LogsRotated.rule(), Limits::default()) {
        assert!(l.items.iter().all(|i| !i.rel_path.is_empty()));
    }
}
