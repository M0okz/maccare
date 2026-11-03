//! Tâches longues : annulation et progression (moteur et frontière C).

use maccare_core::ffi::{
    maccare_measure_dir_task, maccare_scan_rule_task, maccare_string_free, maccare_task_cancel,
    maccare_task_free, maccare_task_new, maccare_task_progress,
};
use maccare_core::rules::{Depth, Rule};
use maccare_core::scan::{measure_children_with, scan_rule_with, RULE_SCAN_BUDGET};
use maccare_core::walk::{measure_paths_with, Budget, Control};
use std::ffi::{CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn base() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let canonical = dir.path().canonicalize().unwrap();
    (dir, canonical)
}

/// `apps` dossiers de `files` fichiers chacun sous `root`.
fn populate(root: &Path, apps: usize, files: usize) {
    for a in 0..apps {
        let d = root.join(format!("app{a}"));
        fs::create_dir_all(&d).unwrap();
        for f in 0..files {
            fs::write(d.join(format!("f{f}")), vec![0u8; 5000]).unwrap();
        }
    }
}

fn rule(root: &Path) -> Rule {
    Rule {
        id: "cache.generic".into(),
        category: "user-cache".into(),
        version: 1,
        root: root.to_string_lossy().into_owned(),
        depth: Depth::PerApp,
        ..Default::default()
    }
}

#[test]
fn progress_counters_track_the_scan() {
    let (_tmp, base) = base();
    populate(&base, 4, 25);

    let control = Control::new();
    let out = scan_rule_with(&rule(&base), Budget::new(RULE_SCAN_BUDGET), &control);
    assert!(!out.cancelled);
    assert_eq!(out.items.len(), 4);
    assert_eq!(control.entries(), 100, "chaque fichier lu est compté");
    let total: u64 = out.items.iter().map(|i| i.size_bytes).sum();
    assert_eq!(control.bytes(), total);
}

#[test]
fn cancelled_before_start_returns_empty_and_flagged() {
    let (_tmp, base) = base();
    populate(&base, 3, 5);

    let control = Control::new();
    control.cancel();
    let out = scan_rule_with(&rule(&base), Budget::new(RULE_SCAN_BUDGET), &control);
    assert!(out.cancelled);
    assert!(out.items.is_empty());

    let m = measure_children_with(&base, Duration::from_secs(20), &control);
    assert!(m.cancelled);
    assert!(m.children.is_empty());

    let sizes = measure_paths_with(&[base.join("app0")], Budget::new(RULE_SCAN_BUDGET), &control);
    assert!(!sizes[0].complete, "une mesure annulée n'est jamais déclarée complète");
}

#[test]
fn cancel_from_another_thread_returns_promptly() {
    let (_tmp, base) = base();
    populate(&base, 40, 100);

    let control = Control::new();
    let c = control.clone();
    let canceller = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(2));
        c.cancel();
        Instant::now()
    });
    let out = scan_rule_with(&rule(&base), Budget::new(RULE_SCAN_BUDGET), &control);
    let returned = Instant::now();
    let asked = canceller.join().unwrap();

    // Le scan a pu finir avant l'annulation sur une machine rapide ; s'il a été annulé, il a
    // rendu la main dans la latence promise.
    if out.cancelled {
        assert!(out.items.is_empty());
        assert!(returned.saturating_duration_since(asked) < Duration::from_millis(250));
    } else {
        assert_eq!(out.items.len(), 40);
    }
}

unsafe fn take(out: *mut i8) -> serde_json::Value {
    assert!(!out.is_null());
    let s = CStr::from_ptr(out).to_str().unwrap().to_owned();
    maccare_string_free(out);
    serde_json::from_str(&s).unwrap()
}

#[test]
fn ffi_task_lifecycle() {
    let (_tmp, base) = base();
    populate(&base, 2, 10);
    let toml = CString::new(format!(
        "id = \"cache.generic\"\ncategory = \"user-cache\"\nversion = 1\nroot = \"{}\"\n",
        base.display()
    ))
    .unwrap();

    unsafe {
        // Scan normal sous jeton : progression lisible ensuite.
        let task = maccare_task_new();
        let v = take(maccare_scan_rule_task(toml.as_ptr(), task));
        assert_eq!(v["cancelled"], false);
        assert_eq!(v["items"].as_array().unwrap().len(), 2);
        let (mut entries, mut bytes) = (0u64, 0u64);
        maccare_task_progress(task, &mut entries, &mut bytes);
        assert_eq!(entries, 20);
        assert!(bytes > 0);
        maccare_task_progress(task, std::ptr::null_mut(), std::ptr::null_mut());
        maccare_task_free(task);

        // Jeton annulé : résultats vides et signalés.
        let task = maccare_task_new();
        maccare_task_cancel(task);
        let v = take(maccare_scan_rule_task(toml.as_ptr(), task));
        assert_eq!(v["cancelled"], true);
        assert!(v["items"].as_array().unwrap().is_empty());
        let input = CString::new(serde_json::json!({ "path": base }).to_string()).unwrap();
        let v = take(maccare_measure_dir_task(input.as_ptr(), task));
        assert_eq!(v["cancelled"], true);
        maccare_task_free(task);

        // Jeton nul : comportement des fonctions sans tâche.
        let v = take(maccare_scan_rule_task(toml.as_ptr(), std::ptr::null()));
        assert_eq!(v["cancelled"], false);
        maccare_task_cancel(std::ptr::null());
        maccare_task_free(std::ptr::null_mut());
    }
}
