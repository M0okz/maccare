//! Tests de la frontière C.

use maccare_core::ffi::{
    maccare_execute_removal, maccare_inspect_paths, maccare_plan_removal, maccare_rule_info,
    maccare_scan_rule, maccare_string_free,
};
use maccare_core::model::FileIdentity;
use serde_json::Value;
use std::ffi::{CStr, CString};
use std::fs;
use std::path::PathBuf;

/// Appelle une fonction FFI chaîne→chaîne et récupère le JSON en libérant la mémoire.
unsafe fn call(f: unsafe extern "C" fn(*const i8) -> *mut i8, arg: &str) -> Value {
    let c = CString::new(arg).unwrap();
    let out = f(c.as_ptr());
    assert!(!out.is_null());
    let s = CStr::from_ptr(out).to_str().unwrap().to_owned();
    maccare_string_free(out);
    serde_json::from_str(&s).unwrap()
}

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

#[test]
fn scan_rule_returns_items() {
    let (_tmp, base) = base();
    let caches = base.join("Caches");
    fs::create_dir_all(caches.join("com.app.one")).unwrap();
    fs::write(caches.join("com.app.one/blob.bin"), "payload").unwrap();

    let toml = format!(
        r#"
        id = "cache.generic"
        category = "user-cache"
        version = 1
        root = "{}"
        depth = "per-app"
    "#,
        caches.display()
    );

    let v = unsafe { call(maccare_scan_rule, &toml) };
    let items = v["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["reason"], "cache.generic");
}

#[test]
fn scan_rule_reports_error_on_bad_toml() {
    let v = unsafe { call(maccare_scan_rule, "not = = toml") };
    assert!(v["error"].is_string());
}

#[test]
fn plan_removal_allows_valid_and_flags_identity_change() {
    let (_tmp, base) = base();
    let file = base.join("Caches/app/data.bin");
    fs::create_dir_all(file.parent().unwrap()).unwrap();
    fs::write(&file, "original").unwrap();
    let id = FileIdentity::of_path(&file).unwrap();

    // Un élément valide, et un second dont l'identité ne correspond pas.
    let input = serde_json::json!({
        "scope_root": base.join("Caches"),
        "items": [
            { "path": file, "identity": { "device": id.device, "inode": id.inode } },
            { "path": file, "identity": { "device": 0, "inode": 0 } },
        ]
    })
    .to_string();

    let v = unsafe { call(maccare_plan_removal, &input) };
    let decisions = v["decisions"].as_array().unwrap();
    assert_eq!(decisions.len(), 2);
    assert_eq!(decisions[0]["allowed"], true);
    assert_eq!(decisions[1]["allowed"], false);
    assert_eq!(decisions[1]["refusal"], "identity-changed");
}

#[test]
fn execute_removal_deletes_allowed_only() {
    let (_tmp, base) = base();
    let good = base.join("Caches/app/good.bin");
    fs::create_dir_all(good.parent().unwrap()).unwrap();
    fs::write(&good, "payload").unwrap();
    let good_id = FileIdentity::of_path(&good).unwrap();

    let input = serde_json::json!({
        "scope_root": base.join("Caches"),
        "items": [
            { "path": good, "identity": { "device": good_id.device, "inode": good_id.inode } },
            // Hors périmètre : doit être refusé et non supprimé.
            { "path": base.join("elsewhere.bin"), "identity": { "device": 1, "inode": 1 } },
        ]
    })
    .to_string();

    let v = unsafe { call(maccare_execute_removal, &input) };
    let results = v["results"].as_array().unwrap();
    assert_eq!(results[0]["allowed"], true);
    assert_eq!(results[0]["removed"], true);
    assert_eq!(results[1]["allowed"], false);
    assert_eq!(results[1]["removed"], false);
    assert!(!good.exists(), "l'élément autorisé a bien été supprimé");
}

#[test]
fn inspect_paths_returns_existing_only() {
    let (_tmp, base) = base();
    let present = base.join("Application Support/MyApp");
    fs::create_dir_all(&present).unwrap();
    fs::write(present.join("data.bin"), "payload").unwrap();
    let absent = base.join("Caches/com.my.app");

    let input = serde_json::json!({
        "category": "uninstall",
        "paths": [present, absent]
    })
    .to_string();

    let v = unsafe { call(maccare_inspect_paths, &input) };
    let items = v["items"].as_array().unwrap();
    assert_eq!(items.len(), 1, "seul le chemin existant est renvoyé");
    assert_eq!(items[0]["reason"], "uninstall");
}

#[test]
fn rule_info_returns_metadata_and_expands_root() {
    let toml = r#"
        id = "downloads.installers"
        category = "downloads-installers"
        version = 1
        root = "~/Downloads"
        title = "Installateurs"
        description = "Déjà utilisés."
        risk = "review"
        icon = "shippingbox.fill"
    "#;
    let v = unsafe { call(maccare_rule_info, toml) };
    assert_eq!(v["title"], "Installateurs");
    assert_eq!(v["risk"], "review");
    assert_eq!(v["icon"], "shippingbox.fill");
    assert_eq!(v["category"], "downloads-installers");
    assert!(
        v["root"].as_str().unwrap().ends_with("/Downloads") && !v["root"].as_str().unwrap().contains('~'),
        "racine développée : {}",
        v["root"]
    );

    // Sans titre, l'identifiant sert de repli.
    let bare = "id = \"x\"\ncategory = \"c\"\nversion = 1\nroot = \"~/x\"\n";
    let v2 = unsafe { call(maccare_rule_info, bare) };
    assert_eq!(v2["title"], "x");
    assert_eq!(v2["risk"], "safe");

    // Une règle invalide renvoie une erreur, jamais une valeur partielle.
    let bad = unsafe { call(maccare_rule_info, "id = \"\"\ncategory = \"c\"\nversion = 1\nroot = \"~/x\"\n") };
    assert!(bad["error"].is_string());
}
