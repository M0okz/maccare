//! Sous-chemins, repères et public des règles ; non-régression des règles livrées.

use maccare_core::model::FileIdentity;
use maccare_core::rules::{Audience, Rule};
use maccare_core::safety::{evaluate_for_rule, Decision, Refusal, SafetyContext};
use maccare_core::scan::scan_rule;
use std::fs;
use std::path::{Path, PathBuf};

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

fn write(path: &Path) {
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, vec![1u8; 5000]).unwrap();
}

fn shipped(rel: &str) -> Rule {
    let p = Path::new(env!("CARGO_MANIFEST_DIR")).join("rules").join(rel);
    Rule::from_toml(&fs::read_to_string(p).unwrap()).unwrap()
}

/// Règle livrée, racine redirigée vers un dossier de test.
fn shipped_at(rel: &str, root: &Path) -> Rule {
    let mut r = shipped(rel);
    r.root = root.to_string_lossy().into_owned();
    r
}

fn names(rule: &Rule) -> Vec<String> {
    let root = PathBuf::from(&rule.root);
    let mut v: Vec<String> = scan_rule(rule)
        .items
        .iter()
        .map(|i| i.path.strip_prefix(&root).unwrap().to_string_lossy().into_owned())
        .collect();
    v.sort();
    v
}

fn id(p: &Path) -> FileIdentity {
    FileIdentity::of_path(p).unwrap()
}

#[test]
fn every_shipped_rule_loads() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("rules");
    let mut count = 0;
    for group in fs::read_dir(&dir).unwrap().flatten() {
        for f in fs::read_dir(group.path()).unwrap().flatten() {
            let src = fs::read_to_string(f.path()).unwrap();
            Rule::from_toml(&src).unwrap_or_else(|e| panic!("{} : {e}", f.path().display()));
            count += 1;
        }
    }
    assert!(count >= 17, "{count} règles");
}

#[test]
fn container_and_electron_rules_stay_narrow() {
    // Toute extension de ces sous-chemins doit être une décision consciente : ce test échoue.
    assert_eq!(shipped("caches/containers.toml").subpaths, vec!["Data/Library/Caches"]);
    assert_eq!(shipped("caches/group-containers.toml").subpaths, vec!["Library/Caches"]);

    let electron = shipped("caches/electron.toml");
    let allowed = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"];
    assert!(electron.subpaths.iter().all(|s| allowed.contains(&s.as_str())), "{:?}", electron.subpaths);
    for forbidden in ["Local Storage", "IndexedDB", "Cookies", "Preferences", "Local State", "Session Storage", "databases"] {
        assert!(!electron.subpaths.iter().any(|s| s.contains(forbidden)), "{forbidden}");
    }
    assert!(!electron.require_any.is_empty(), "Electron exige un repère");
}

#[test]
fn audience_defaults_to_everyone() {
    assert_eq!(shipped("caches/generic.toml").audience, Audience::Everyone);
    assert_eq!(shipped("caches/containers.toml").audience, Audience::Everyone);
    for r in ["xcode/device-support.toml", "xcode/archives.toml", "xcode/device-logs.toml"] {
        assert_eq!(shipped(r).audience, Audience::Developer, "{r}");
    }
}

#[test]
fn invalid_subpaths_and_markers_are_rejected() {
    let head = "id = \"x\"\ncategory = \"x\"\nversion = 1\nroot = \"/tmp\"\n";
    for bad in ["subpaths = [\"../x\"]", "subpaths = [\"/abs\"]", "subpaths = [\"a/../b\"]", "subpaths = [\"\"]",
                "require_any = [\"a/b\"]", "require_any = [\"..\"]", "depth = \"flat\"\nsubpaths = [\"a\"]"] {
        assert!(Rule::from_toml(&format!("{head}{bad}\n")).is_err(), "{bad}");
    }
}

#[test]
fn containers_propose_only_their_caches() {
    let (_tmp, base) = base();
    let root = base.join("Containers");
    write(&root.join("com.app.one/Data/Library/Caches/blob"));
    write(&root.join("com.app.one/Data/Documents/rapport.txt"));
    write(&root.join("com.app.one/Data/Library/Application Support/base.db"));
    write(&root.join("com.app.two/Data/Library/Preferences/p.plist")); // pas de Caches
    write(&root.join("com.apple.mail/Data/Library/Caches/blob"));
    // Caches qui pointe vers des documents : jamais proposé.
    write(&base.join("Docs/secret.txt"));
    fs::create_dir_all(root.join("com.app.three/Data/Library")).unwrap();
    std::os::unix::fs::symlink(base.join("Docs"), root.join("com.app.three/Data/Library/Caches")).unwrap();

    let rule = shipped_at("caches/containers.toml", &root);
    assert_eq!(names(&rule), vec!["com.app.one/Data/Library/Caches"]);
}

#[test]
fn markers_are_fail_closed() {
    let (_tmp, base) = base();
    let root = base.join("Application Support");
    write(&root.join("Slack/Code Cache/js/a"));
    write(&root.join("Slack/Cache/Cache_Data/b"));
    write(&root.join("Slack/Local Storage/leveldb/c"));
    write(&root.join("NotElectron/Cache/d")); // pas de repère Chromium

    let rule = shipped_at("caches/electron.toml", &root);
    assert_eq!(names(&rule), vec!["Slack/Cache", "Slack/Code Cache"]);
}

#[test]
fn removal_revalidates_the_exact_subpath() {
    let (_tmp, base) = base();
    let root = base.join("Containers");
    let caches = root.join("com.app.one/Data/Library/Caches");
    write(&caches.join("blob"));
    write(&root.join("com.app.one/Data/Documents/rapport.txt"));
    let rule = shipped_at("caches/containers.toml", &root);
    let ctx = SafetyContext::new([base.join("Docs")]);

    assert_eq!(evaluate_for_rule(&ctx, &caches, &rule, id(&caches)), Decision::Allowed);

    for wrong in [
        root.join("com.app.one"),
        root.join("com.app.one/Data/Documents"),
        caches.join("blob"),
        root.join("com.app.one/Data/Library"),
    ] {
        assert!(
            matches!(evaluate_for_rule(&ctx, &wrong, &rule, id(&wrong)), Decision::Refused(Refusal::OutsideScope { .. })),
            "{}",
            wrong.display()
        );
    }

    // Le sous-chemin devient un lien vers l'extérieur après l'analyse : refusé.
    let before = id(&caches);
    fs::rename(&caches, root.join("com.app.one/Data/Library/Caches.old")).unwrap();
    write(&base.join("Docs/secret.txt"));
    std::os::unix::fs::symlink(base.join("Docs"), &caches).unwrap();
    assert!(matches!(evaluate_for_rule(&ctx, &caches, &rule, before), Decision::Refused(Refusal::SymlinkInPath(_))));
    assert!(base.join("Docs/secret.txt").exists());

    // Repère disparu depuis l'analyse : refusé.
    let app = base.join("Application Support");
    write(&app.join("Slack/Code Cache/a"));
    write(&app.join("Slack/Cache/b"));
    let electron = shipped_at("caches/electron.toml", &app);
    let cache = app.join("Slack/Cache");
    fs::remove_dir_all(app.join("Slack/Code Cache")).unwrap();
    assert!(matches!(evaluate_for_rule(&ctx, &cache, &electron, id(&cache)), Decision::Refused(Refusal::RuleMismatch(_))));
}

#[test]
fn shipped_generic_rules_behave_as_before() {
    // Non-régression : sans sous-chemin, une règle propose toujours les entrées elles-mêmes.
    let (_tmp, base) = base();
    let caches = base.join("Caches");
    write(&caches.join("com.app.one/blob"));
    write(&caches.join("org.tool/blob"));
    write(&caches.join("com.apple.Safari/blob"));
    fs::write(caches.join(".DS_Store"), b"x").unwrap();
    assert_eq!(names(&shipped_at("caches/generic.toml", &caches)), vec!["com.app.one", "org.tool"]);

    let logs = base.join("Logs");
    write(&logs.join("App/log.txt"));
    write(&logs.join("DiagnosticReports/crash.ips"));
    assert_eq!(names(&shipped_at("logs/user.toml", &logs)), vec!["App", "DiagnosticReports"]);
}
