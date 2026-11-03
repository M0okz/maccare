//! Simulateurs Xcode : lecture des réponses de simctl et liste fermée au moment de supprimer.

use maccare_core::simulators::{
    delete_runtimes, delete_simulators, is_uuid, list, parse_devices, parse_runtimes, runtime_name, simctl_in,
};
use maccare_core::walk::Control;
use std::process::Command;

const DEVICES: &str = r#"{"devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
    {"dataPath": "/x", "udid": "4BD77194-FA53-40F8-9402-A37478082094", "lastUsedAt": "2026-10-18T10:12:43Z",
     "isAvailable": true, "state": "Shutdown", "name": "iPhone 15"},
    {"udid": "--help", "isAvailable": true, "state": "Shutdown", "name": "Piège"}
  ],
  "com.apple.CoreSimulator.SimRuntime.watchOS-10-0": [
    {"udid": "E792023B-CD83-4658-A0F5-3C85F2230A15", "isAvailable": false, "state": "Booted", "name": "Watch"}
  ]}}"#;

const RUNTIMES: &str = r#"{
  "8E06CBCA-8C62-4BDD-9B43-8CCF0128DBA4": {"identifier": "8E06CBCA-8C62-4BDD-9B43-8CCF0128DBA4", "deletable": true,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-10-0", "sizeBytes": 3814435665, "lastUsedAt": "2026-10-01T00:00:00Z"},
  "bad": {"identifier": "rm -rf", "deletable": true, "runtimeIdentifier": "x", "sizeBytes": 1}
}"#;

#[test]
fn parses_simctl_answers_and_drops_malformed_ids() {
    let sims = parse_devices(DEVICES).unwrap();
    assert_eq!(sims.len(), 2, "l'UDID « --help » est écarté");
    let ios = sims.iter().find(|s| s.name == "iPhone 15").unwrap();
    assert_eq!(ios.runtime, "iOS 17.5");
    assert_eq!(ios.state, "Shutdown");
    assert!(ios.available);
    assert_eq!(ios.last_used.as_deref(), Some("2026-10-18T10:12:43Z"));
    let watch = sims.iter().find(|s| s.name == "Watch").unwrap();
    assert!(!watch.available && watch.state == "Booted");

    let rts = parse_runtimes(RUNTIMES).unwrap();
    assert_eq!(rts.len(), 1, "identifiant non-UUID écarté");
    assert_eq!(rts[0].name, "watchOS 10.0");
    assert_eq!(rts[0].size_bytes, 3_814_435_665);
    assert!(rts[0].deletable);

    assert!(parse_devices("pas du json").is_err());
    assert!(parse_devices("{}").is_err());
}

#[test]
fn identifiers_must_look_like_uuids() {
    assert!(is_uuid("4BD77194-FA53-40F8-9402-A37478082094"));
    for bad in ["", "--help", "all", "4BD77194-FA53-40F8-9402", "4BD77194-FA53-40F8-9402-A3747808209Z", "../../x"] {
        assert!(!is_uuid(bad), "{bad}");
    }
    assert_eq!(runtime_name("com.apple.CoreSimulator.SimRuntime.visionOS-2-0"), "visionOS 2.0");
}

#[test]
fn simctl_is_only_found_where_it_really_is() {
    // Sans simctl dans le dossier développeur (Mac sans Xcode, ou outils en ligne de commande
    // seuls) : rien n'est trouvé, donc rien n'est lancé.
    let dir = tempfile::tempdir().unwrap();
    assert!(simctl_in(dir.path()).is_none());
    std::fs::create_dir_all(dir.path().join("usr/bin/simctl")).unwrap(); // un dossier, pas un outil
    assert!(simctl_in(dir.path()).is_none());
    let dir2 = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir2.path().join("usr/bin")).unwrap();
    std::fs::write(dir2.path().join("usr/bin/simctl"), b"").unwrap();
    assert_eq!(simctl_in(dir2.path()), Some(dir2.path().join("usr/bin/simctl")));
}

#[test]
fn unlisted_or_malformed_ids_are_never_deleted() {
    // Sans Xcode, la relecture échoue et tout est refusé ; avec Xcode, ces identifiants ne
    // figurent pas dans la liste. Dans les deux cas, rien n'est supprimé.
    let control = Control::new();
    let r = delete_simulators(&["all".into(), "00000000-0000-0000-0000-000000000000".into()], &control);
    assert!(r.iter().all(|x| !x.removed));
    let r = delete_runtimes(&["--all".into(), "00000000-0000-0000-0000-000000000000".into()], &control);
    assert!(r.iter().all(|x| !x.removed));
}

/// Cycle complet sur un simulateur créé pour l'occasion : refus tant qu'il est allumé, puis
/// suppression. Demande Xcode : `cargo test --test simulators -- --ignored`.
#[test]
#[ignore]
fn deletes_only_a_listed_shutdown_simulator() {
    let control = Control::new();
    let before = list(&control);
    assert!(before.xcode, "Xcode requis");
    let runtime = before
        .simulators
        .iter()
        .find(|s| s.available && s.runtime.starts_with("iOS"))
        .map(|s| s.runtime_identifier.clone())
        .expect("un runtime iOS installé");

    let out = Command::new("/usr/bin/xcrun")
        .args(["simctl", "create", "MacCare-test", "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation", &runtime])
        .output()
        .unwrap();
    let udid = String::from_utf8_lossy(&out.stdout).trim().to_string();
    assert!(is_uuid(&udid), "création : {}", String::from_utf8_lossy(&out.stderr));

    // Allumé : refusé.
    assert!(Command::new("/usr/bin/xcrun").args(["simctl", "boot", &udid]).status().unwrap().success());
    let r = delete_simulators(std::slice::from_ref(&udid), &control);
    let _ = Command::new("/usr/bin/xcrun").args(["simctl", "shutdown", &udid]).status();
    assert_eq!(r[0].error.as_deref(), Some("booted"));
    assert!(!r[0].removed);

    // Éteint : supprimé, et absent de la liste ensuite.
    let r = delete_simulators(std::slice::from_ref(&udid), &control);
    assert!(r[0].removed, "{:?}", r[0].error);
    assert!(!list(&control).simulators.iter().any(|s| s.udid == udid));
}
