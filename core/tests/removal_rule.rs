//! Re-validation d'une sélection contre la règle qui l'a proposée (`evaluate_for_rule`), dont la
//! dérogation « liste blanche » pour les arbres protégés comme `~/Downloads`.

use maccare_core::clean::{execute_for_rule, RemovalMode};
use maccare_core::ffi::{maccare_plan_removal, maccare_string_free};
use maccare_core::model::{FileIdentity, ScanItem};
use maccare_core::rules::{Depth, Exclude, Include, Rule};
use maccare_core::safety::{evaluate_for_rule, Decision, Refusal, SafetyContext};
use std::ffi::{CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

/// Règle « installateurs » sur `root`, à liste blanche `.dmg`.
fn installers(root: &Path) -> Rule {
    Rule {
        id: "downloads.installers".into(),
        category: "downloads-installers".into(),
        version: 1,
        root: root.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        include: vec![Include::NameSuffix { ends_with: ".dmg".into() }],
        ..Default::default()
    }
}

/// Contexte où `downloads` est protégé récursivement, comme `~/Downloads` en production.
fn protecting(downloads: &Path) -> SafetyContext {
    SafetyContext::new([downloads.to_path_buf()])
}

fn id(path: &Path) -> FileIdentity {
    FileIdentity::of_path(path).unwrap()
}

fn refusal(d: Decision) -> Refusal {
    match d {
        Decision::Refused(r) => r,
        Decision::Allowed => panic!("refus attendu"),
    }
}

#[test]
fn whitelisted_direct_child_of_protected_tree_is_allowed() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads).unwrap();
    let dmg = downloads.join("App.dmg");
    fs::write(&dmg, "x").unwrap();

    let ctx = protecting(&downloads);
    let rule = installers(&downloads);
    assert_eq!(evaluate_for_rule(&ctx, &dmg, &rule, id(&dmg)), Decision::Allowed);
}

#[test]
fn paths_outside_the_rule_are_refused() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    let nested = downloads.join("sous/dossier/x.dmg");
    let txt = downloads.join("notes.txt");
    fs::create_dir_all(nested.parent().unwrap()).unwrap();
    fs::write(&nested, "x").unwrap();
    fs::write(&txt, "x").unwrap();

    let ctx = protecting(&downloads);
    let rule = installers(&downloads);

    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &nested, &rule, id(&nested))),
        Refusal::OutsideScope { .. }
    ), "un .dmg imbriqué n'est pas un enfant direct de la racine");
    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &txt, &rule, id(&txt))),
        Refusal::RuleMismatch(_)
    ), "hors liste blanche");
    let elsewhere = base.join("ailleurs.dmg");
    fs::write(&elsewhere, "x").unwrap();
    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &elsewhere, &rule, id(&elsewhere))),
        Refusal::OutsideScope { .. }
    ));
}

#[test]
fn rule_without_whitelist_cannot_enter_protected_tree() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads).unwrap();
    let f = downloads.join("App.dmg");
    fs::write(&f, "x").unwrap();

    let ctx = protecting(&downloads);
    let mut rule = installers(&downloads);
    rule.include.clear();
    assert!(matches!(refusal(evaluate_for_rule(&ctx, &f, &rule, id(&f))), Refusal::Protected(_)));
}

#[test]
fn protected_entry_itself_is_never_whitelisted() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads).unwrap();

    let ctx = protecting(&downloads);
    // Règle (malveillante ou erronée) dont la racine est le parent et la liste blanche vise le
    // dossier protégé lui-même.
    let mut rule = installers(&base);
    rule.include = vec![Include::NameSuffix { ends_with: "downloads".into() }];
    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &downloads, &rule, id(&downloads))),
        Refusal::Protected(_)
    ));
}

#[test]
fn identity_symlink_and_name_exclusions_still_apply() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads).unwrap();
    let dmg = downloads.join("App.dmg");
    fs::write(&dmg, "x").unwrap();
    let ctx = protecting(&downloads);

    // Identité changée depuis le scan : remplacé par un autre fichier.
    let before = id(&dmg);
    fs::remove_file(&dmg).unwrap();
    fs::write(&dmg, "autre").unwrap();
    let rule = installers(&downloads);
    if id(&dmg) != before {
        assert!(matches!(
            refusal(evaluate_for_rule(&ctx, &dmg, &rule, before)),
            Refusal::IdentityChanged { .. }
        ));
    }

    // Lien symbolique proposé comme candidat.
    let link = downloads.join("Lien.dmg");
    std::os::unix::fs::symlink(base.join("cible.dmg"), &link).unwrap();
    fs::write(base.join("cible.dmg"), "x").unwrap();
    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &link, &rule, id(&link))),
        Refusal::SymlinkInPath(_)
    ));

    // Exclusion ajoutée par l'utilisateur après le scan.
    let mut excluded = installers(&downloads);
    excluded.exclude.push(Exclude::Name { equals: "App.dmg".into() });
    assert!(matches!(
        refusal(evaluate_for_rule(&ctx, &dmg, &excluded, id(&dmg))),
        Refusal::RuleMismatch(_)
    ));
}

#[test]
fn direct_delete_for_rule_removes_only_matching_items() {
    let (_tmp, base) = base();
    let downloads = base.join("Downloads");
    fs::create_dir_all(&downloads).unwrap();
    let dmg = downloads.join("App.dmg");
    let txt = downloads.join("garder.txt");
    fs::write(&dmg, "x").unwrap();
    fs::write(&txt, "x").unwrap();

    let items: Vec<ScanItem> = [&dmg, &txt]
        .iter()
        .map(|p| ScanItem::new((*p).clone(), "c", "r", 0, false, id(p)))
        .collect();
    let results = execute_for_rule(&protecting(&downloads), &installers(&downloads), &items, RemovalMode::DirectDelete);

    assert!(results[0].removed);
    assert!(!dmg.exists());
    assert!(!results[1].removed);
    assert!(txt.exists(), "le fichier hors règle est intact");
}

unsafe fn plan(input: &str) -> serde_json::Value {
    let c = CString::new(input).unwrap();
    let out = maccare_plan_removal(c.as_ptr());
    let s = CStr::from_ptr(out).to_str().unwrap().to_owned();
    maccare_string_free(out);
    serde_json::from_str(&s).unwrap()
}

#[test]
fn ffi_plan_with_rule_reports_rule_mismatch_and_rejects_invalid_rules() {
    let (_tmp, base) = base();
    let dir = base.join("Telechargements");
    fs::create_dir_all(&dir).unwrap();
    let dmg = dir.join("App.dmg");
    let txt = dir.join("notes.txt");
    fs::write(&dmg, "x").unwrap();
    fs::write(&txt, "x").unwrap();

    let rule = format!(
        "id = \"downloads.installers\"\ncategory = \"d\"\nversion = 1\nroot = \"{}\"\n\n[[include]]\nkind = \"name-suffix\"\nends_with = \".dmg\"\n",
        dir.display()
    );
    let item = |p: &Path| {
        let i = id(p);
        serde_json::json!({ "path": p, "identity": { "device": i.device, "inode": i.inode } })
    };
    let input = serde_json::json!({ "rule": rule, "items": [item(&dmg), item(&txt)] }).to_string();
    let v = unsafe { plan(&input) };
    let d = v["decisions"].as_array().unwrap();
    assert_eq!(d[0]["allowed"], true);
    assert_eq!(d[1]["allowed"], false);
    assert_eq!(d[1]["refusal"], "rule-mismatch");

    // Règle invalide : échec global, aucune décision rendue.
    let bad = serde_json::json!({ "rule": "id = \"\"", "items": [item(&dmg)] }).to_string();
    let v = unsafe { plan(&bad) };
    assert!(v["error"].is_string());
    assert!(v.get("decisions").is_none());

    // Ni règle ni périmètre : refus.
    let none = serde_json::json!({ "items": [item(&dmg)] }).to_string();
    assert!(unsafe { plan(&none) }["error"].is_string());
}
