//! Démarrage : agents (liste fermée, désactivation réversible et atomique) et préférences cassées.

use maccare_core::model::FileIdentity;
use maccare_core::rules::{is_broken_plist, Rule};
use maccare_core::safety::{evaluate_for_rule, Decision, Refusal, SafetyContext};
use maccare_core::scan::scan_rule;
use maccare_core::startup::{
    disable_in, enable_in, list_in, parse_launchctl_list, program_missing, read_registry, Dirs, Launcher, Scope,
};
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn id(p: &Path) -> FileIdentity {
    FileIdentity::of_path(p).unwrap()
}

/// `launchctl` factice : état chargé en mémoire, pannes à la demande, journal des appels.
#[derive(Default)]
struct Fake {
    loaded: RefCell<HashMap<String, Option<u32>>>,
    fail_bootout: bool,
    fail_bootstrap: bool,
    fail_list: bool,
    calls: RefCell<Vec<String>>,
}

impl Launcher for Fake {
    fn loaded(&self) -> Result<HashMap<String, Option<u32>>, String> {
        if self.fail_list {
            return Err("launchctl muet".into());
        }
        Ok(self.loaded.borrow().clone())
    }
    fn bootout(&self, plist: &Path) -> Result<(), String> {
        self.calls.borrow_mut().push(format!("bootout {}", plist.display()));
        if self.fail_bootout {
            return Err("refus simulé".into());
        }
        let label = plist.file_stem().unwrap().to_string_lossy().into_owned();
        self.loaded.borrow_mut().remove(&label);
        Ok(())
    }
    fn bootstrap(&self, plist: &Path) -> Result<(), String> {
        self.calls.borrow_mut().push(format!("bootstrap {}", plist.display()));
        if self.fail_bootstrap {
            return Err("refus simulé".into());
        }
        let label = plist.file_stem().unwrap().to_string_lossy().into_owned();
        self.loaded.borrow_mut().insert(label, Some(1));
        Ok(())
    }
}

fn agent_plist(label: &str, program: &str) -> String {
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>{label}</string>
<key>ProgramArguments</key><array><string>{program}</string></array></dict></plist>"#
    )
}

fn setup() -> (tempfile::TempDir, PathBuf, Dirs) {
    let (tmp, base) = base();
    let dirs = Dirs {
        user: base.join("LaunchAgents"),
        disabled: base.join("MacCare/Disabled LaunchAgents"),
        system: vec![base.join("SystemAgents")],
    };
    fs::create_dir_all(&dirs.user).unwrap();
    fs::create_dir_all(&dirs.system[0]).unwrap();
    let w = |dir: &Path, label: &str, prog: &str| fs::write(dir.join(format!("{label}.plist")), agent_plist(label, prog)).unwrap();
    w(&dirs.user, "org.example.ok", "/bin/sh");
    w(&dirs.user, "org.example.orphan", "/Applications/Disparue.app/Contents/MacOS/x");
    w(&dirs.user, "com.apple.example", "/bin/sh");
    w(&dirs.user, "homebrew.mxcl.redis", "/bin/sh");
    // Fichier Apple avec un autre Label : reconnu Apple par son nom de fichier.
    fs::write(dirs.user.join("com.apple.deguise.plist"), agent_plist("org.autre.label", "/bin/sh")).unwrap();
    w(&dirs.system[0], "org.example.system", "/bin/sh");
    fs::write(dirs.user.join("illisible.plist"), b"pas un plist").unwrap();
    std::os::unix::fs::symlink(dirs.user.join("org.example.ok.plist"), dirs.user.join("lien.plist")).unwrap();
    (tmp, base, dirs)
}

#[test]
fn lists_with_orphans_owners_and_scopes() {
    let (_tmp, _base, dirs) = setup();
    let fake = Fake::default();
    fake.loaded.borrow_mut().insert("org.example.ok".into(), Some(42));
    let agents = list_in(&dirs, &fake);
    let by = |l: &str| agents.iter().find(|a| a.label == l).unwrap_or_else(|| panic!("{l}"));

    assert!(by("org.example.ok").running && !by("org.example.ok").orphan);
    assert!(by("org.example.orphan").orphan);
    assert!(by("com.apple.example").apple && !by("com.apple.example").can_disable());
    assert_eq!(by("homebrew.mxcl.redis").managed_by.as_deref(), Some("Homebrew"));
    assert_eq!(by("org.example.system").scope, Scope::System);
    assert!(!by("org.example.system").can_disable());
    assert!(!by("org.example.system").state_known, "aucun état affiché pour le système");
    assert!(by("org.example.ok").state_known);
    assert!(by("org.autre.label").apple && !by("org.autre.label").can_disable());
    assert!(by("illisible").program.is_none(), "plist illisible : listé sans programme");
    assert!(!agents.iter().any(|a| a.path.ends_with("lien.plist")), "un lien n'est jamais listé");

    let parsed = parse_launchctl_list("PID\tStatus\tLabel\n123\t0\torg.a\n-\t0\torg.b\n");
    assert_eq!(parsed.get("org.a"), Some(&Some(123)));
    assert_eq!(parsed.get("org.b"), Some(&None));
}

#[test]
fn disable_then_enable_round_trip() {
    let (_tmp, _base, dirs) = setup();
    let fake = Fake::default();
    fake.loaded.borrow_mut().insert("org.example.ok".into(), Some(42));
    let original = dirs.user.join("org.example.ok.plist");

    let stored = disable_in(&dirs, &original, id(&original), &fake).unwrap();
    assert!(!original.exists() && stored.exists());
    assert!(fake.calls.borrow()[0].starts_with("bootout"));
    assert_eq!(read_registry(&dirs).len(), 1);

    // Visible comme désactivé, avec son origine, même pour une nouvelle lecture (après relance).
    let agents = list_in(&dirs, &fake);
    let d = agents.iter().find(|a| a.scope == Scope::Disabled).unwrap();
    assert_eq!(d.original_path.as_deref(), Some(original.as_path()));

    let back = enable_in(&dirs, &stored, id(&stored), &fake).unwrap();
    assert_eq!(back, original);
    assert!(original.exists() && !stored.exists());
    assert!(fake.calls.borrow().last().unwrap().starts_with("bootstrap"));
    assert!(read_registry(&dirs).is_empty());
}

#[test]
fn not_loaded_agent_is_not_booted_out() {
    let (_tmp, _base, dirs) = setup();
    let fake = Fake::default();
    let p = dirs.user.join("org.example.orphan.plist");
    disable_in(&dirs, &p, id(&p), &fake).unwrap();
    assert!(fake.calls.borrow().is_empty());
}

#[test]
fn refuses_anything_outside_the_closed_list() {
    let (_tmp, base, dirs) = setup();
    let fake = Fake::default();
    let sys = dirs.system[0].join("org.example.system.plist");
    assert_eq!(disable_in(&dirs, &sys, id(&sys), &fake).unwrap_err(), "not-listed");
    let apple = dirs.user.join("com.apple.example.plist");
    assert_eq!(disable_in(&dirs, &apple, id(&apple), &fake).unwrap_err(), "apple");
    let ok = dirs.user.join("org.example.ok.plist");
    let wrong = FileIdentity { device: id(&ok).device, inode: id(&ok).inode + 1 };
    assert_eq!(disable_in(&dirs, &ok, wrong, &fake).unwrap_err(), "identity-changed");
    let elsewhere = base.join("ailleurs.plist");
    fs::write(&elsewhere, agent_plist("x", "/bin/sh")).unwrap();
    assert_eq!(disable_in(&dirs, &elsewhere, id(&elsewhere), &fake).unwrap_err(), "not-listed");
    let link = dirs.user.join("lien.plist");
    assert_eq!(disable_in(&dirs, &link, id(&link), &fake).unwrap_err(), "not-listed");
    // Réactiver un agent jamais mis de côté : refusé.
    assert_eq!(enable_in(&dirs, &ok, id(&ok), &fake).unwrap_err(), "not-listed");
    assert!(fake.calls.borrow().is_empty(), "aucun appel à launchctl pour un refus");
    assert!(ok.exists() && apple.exists() && sys.exists());
}

#[test]
fn failures_roll_back_to_the_previous_state() {
    use std::os::unix::fs::PermissionsExt;
    let (_tmp, _base, dirs) = setup();
    let ok = dirs.user.join("org.example.ok.plist");

    // Arrêt refusé : rien ne bouge.
    let fake = Fake { fail_bootout: true, ..Default::default() };
    fake.loaded.borrow_mut().insert("org.example.ok".into(), Some(42));
    assert!(disable_in(&dirs, &ok, id(&ok), &fake).is_err());
    assert!(ok.exists());

    // Arrêt réussi mais déplacement impossible : l'agent est remis en route, à sa place.
    let fake = Fake::default();
    fake.loaded.borrow_mut().insert("org.example.ok".into(), Some(42));
    fs::create_dir_all(&dirs.disabled).unwrap();
    fs::set_permissions(&dirs.disabled, fs::Permissions::from_mode(0o555)).unwrap();
    let r = disable_in(&dirs, &ok, id(&ok), &fake);
    fs::set_permissions(&dirs.disabled, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(r.is_err());
    assert!(ok.exists());
    let calls = fake.calls.borrow().clone();
    assert!(calls[0].starts_with("bootout") && calls[1].starts_with("bootstrap"), "{calls:?}");

    // Réactivation : emplacement d'origine occupé → refus, rien n'est écrasé.
    let fake = Fake::default();
    let stored = disable_in(&dirs, &ok, id(&ok), &fake).unwrap();
    fs::write(&ok, b"nouveau fichier").unwrap();
    assert_eq!(enable_in(&dirs, &stored, id(&stored), &fake).unwrap_err(), "occupied");
    assert_eq!(fs::read(&ok).unwrap(), b"nouveau fichier");
    fs::remove_file(&ok).unwrap();

    // Réactivation : chargement refusé → l'agent reste mis de côté, registre intact.
    let fake = Fake { fail_bootstrap: true, ..Default::default() };
    assert!(enable_in(&dirs, &stored, id(&stored), &fake).is_err());
    assert!(stored.exists() && !ok.exists());
    assert_eq!(read_registry(&dirs).len(), 1);
}

fn set_old(path: &Path) {
    let f = fs::File::options().write(true).open(path).unwrap();
    f.set_modified(SystemTime::now() - Duration::from_secs(3600)).unwrap();
}

#[test]
fn only_parse_errors_make_a_broken_preference() {
    use std::os::unix::fs::PermissionsExt;
    let (_tmp, base) = base();
    let prefs = base.join("Preferences");
    fs::create_dir_all(&prefs).unwrap();
    let write = |name: &str, data: &[u8], old: bool| {
        let p = prefs.join(name);
        fs::write(&p, data).unwrap();
        if old {
            set_old(&p);
        }
        p
    };
    let valid = write("org.ok.plist", agent_plist("a", "/bin/sh").as_bytes(), true);
    let broken = write("org.casse.plist", b"\x00\x01 pas un plist", true);
    let fresh = write("org.recent.plist", b"\x00\x01 pas un plist", false);
    let empty = write("org.vide.plist", b"", true);
    let not_plist = write("notes.txt", b"\x00\x01", true);
    let locked = write("org.verrou.plist", b"\x00\x01 pas un plist", true);
    write("com.apple.casse.plist", b"\x00\x01 pas un plist", true);
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o000)).unwrap();

    assert!(is_broken_plist(&broken));
    for p in [&valid, &fresh, &empty, &not_plist, &locked] {
        assert!(!is_broken_plist(p), "{}", p.display());
    }

    let mut rule = Rule::from_toml(&fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("rules/prefs/broken.toml")).unwrap()).unwrap();
    rule.root = prefs.to_string_lossy().into_owned();
    let found: Vec<_> = scan_rule(&rule).items.into_iter().map(|i| i.path).collect();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!(found, vec![broken.clone()], "Apple exclu, seul le fichier cassé");

    // Réparé depuis l'analyse : le retrait est refusé (contenu réanalysé).
    let before = FileIdentity::of_path(&broken).unwrap();
    fs::write(&broken, agent_plist("r", "/bin/sh")).unwrap();
    set_old(&broken);
    let d = evaluate_for_rule(&SafetyContext::new(Vec::<PathBuf>::new()), &broken, &rule, before);
    assert!(matches!(d, Decision::Refused(Refusal::RuleMismatch(_))), "{d:?}");
}

#[test]
fn unknown_launchctl_state_refuses_to_disable() {
    let (_tmp, _base, dirs) = setup();
    let fake = Fake { fail_list: true, ..Default::default() };
    let ok = dirs.user.join("org.example.ok.plist");
    assert_eq!(disable_in(&dirs, &ok, id(&ok), &fake).unwrap_err(), "launchctl-unknown");
    assert!(ok.exists(), "rien n'a bougé");
    assert!(fake.calls.borrow().is_empty());
    // La liste reste affichable, sans état.
    assert!(list_in(&dirs, &fake).iter().all(|a| !a.state_known));
}

#[test]
fn orphan_only_when_truly_absent() {
    use std::os::unix::fs::PermissionsExt;
    let (_tmp, base) = base();
    // Vraiment absent, dans un dossier lisible (y compris plusieurs niveaux manquants).
    assert!(program_missing(base.join("Disparue.app/Contents/MacOS/x").to_str().unwrap()));
    // Lien cassé sur le chemin (version supprimée derrière un lien « Current ») : absent.
    fs::create_dir_all(base.join("Updater")).unwrap();
    std::os::unix::fs::symlink(base.join("Updater/1.0"), base.join("Updater/Current")).unwrap();
    assert!(program_missing(base.join("Updater/Current/App.app/Contents/MacOS/app").to_str().unwrap()));
    // Lien vers un disque peut-être débranché : inconnu, donc pas orphelin.
    std::os::unix::fs::symlink("/Volumes/DisqueAbsent/outil", base.join("outil")).unwrap();
    assert!(!program_missing(base.join("outil").to_str().unwrap()));
    // Présent, relatif, ou sur un volume possiblement démonté : jamais orphelin.
    assert!(!program_missing("/bin/sh"));
    assert!(!program_missing("relatif/x"));
    assert!(!program_missing("/Volumes/DisqueAbsent/app/x"));
    // Sous un dossier illisible (droits, TCC) : on ne sait pas, donc pas orphelin.
    let locked = base.join("verrou");
    fs::create_dir_all(locked.join("dedans")).unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o000)).unwrap();
    let r = program_missing(locked.join("dedans/x").to_str().unwrap());
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(!r);
}

#[test]
fn openstep_preferences_are_valid() {
    let (_tmp, base) = base();
    let p = base.join("org.openstep.plist");
    fs::write(&p, "{\n  \"NSWindow Frame\" = \"0 0 100 100\";\n  liste = (1, 2);\n}").unwrap();
    set_old(&p);
    assert!(!is_broken_plist(&p));
    let truncated = base.join("org.tronque.plist");
    fs::write(&truncated, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>a</key>").unwrap();
    set_old(&truncated);
    assert!(is_broken_plist(&truncated));
}
