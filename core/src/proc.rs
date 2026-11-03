//! Lancement borné d'outils système (`simctl`, `launchctl`…).
//!
//! Jamais via un shell : le programme et ses arguments sont passés tels quels. L'appel est borné
//! dans le temps et annulable ; un outil qui ne répond pas est tué plutôt que de figer l'app.

use crate::walk::Control;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// Lance `program` avec `args` et renvoie sa sortie standard en cas de succès, sinon la dernière
/// ligne de ses erreurs (ou `introuvable`, `ne répond pas`, `annulé`).
pub fn run(program: &Path, args: &[&str], timeout: Duration, control: &Arc<Control>) -> Result<String, String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|_| "introuvable".to_string())?;
    // Lecture des sorties dans des threads : un tampon plein ne doit pas bloquer l'outil.
    let mut stdout = child.stdout.take().expect("sortie redirigée");
    let mut stderr = child.stderr.take().expect("erreurs redirigées");
    let out_reader = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = stdout.read_to_string(&mut s);
        s
    });
    let err_reader = std::thread::spawn(move || {
        let mut s = String::new();
        let _ = stderr.read_to_string(&mut s);
        s
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        if let Some(st) = child.try_wait().map_err(|e| e.to_string())? {
            break st;
        }
        if control.is_cancelled() || Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(if control.is_cancelled() { "annulé".into() } else { "ne répond pas".into() });
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    let out = out_reader.join().unwrap_or_default();
    let err = err_reader.join().unwrap_or_default();
    if status.success() {
        Ok(out)
    } else {
        Err(err.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("échec").trim().to_string())
    }
}
