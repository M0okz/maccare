//! Mesure le temps de scan de chaque règle livrée sur le compte courant, puis d'un niveau
//! d'« Espace disque ». Ne supprime rien.
//!
//! `cargo run --release --example bench_scan [dossier-à-mesurer]`

use maccare_core::rules::Rule;
use maccare_core::dupes::find_duplicates;
use maccare_core::large::{find_large_files, DEFAULT_BUDGET, DEFAULT_LIMIT, DEFAULT_MIN_BYTES};
use maccare_core::scan::{measure_children, scan_rule, MEASURE_DEFAULT_BUDGET};
use maccare_core::walk::{Budget, Control};
use std::path::{Path, PathBuf};
use std::time::Instant;

fn main() {
    let rules_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("rules");
    let mut files: Vec<PathBuf> = Vec::new();
    for group in std::fs::read_dir(&rules_dir).unwrap().flatten() {
        for f in std::fs::read_dir(group.path()).unwrap().flatten() {
            files.push(f.path());
        }
    }
    files.sort();

    let total = Instant::now();
    for f in &files {
        let rule = Rule::from_toml(&std::fs::read_to_string(f).unwrap()).unwrap();
        let t = Instant::now();
        let out = scan_rule(&rule);
        let bytes: u64 = out.items.iter().map(|i| i.size_bytes).sum();
        println!(
            "{:<28} {:>5} éléments {:>10.1} Mo {:>8.0} ms  ({} avert.)",
            rule.id,
            out.items.len(),
            bytes as f64 / 1e6,
            t.elapsed().as_secs_f64() * 1000.0,
            out.warnings.len()
        );
    }
    println!("total règles : {:.0} ms", total.elapsed().as_secs_f64() * 1000.0);

    let target = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap()).join("Library"));
    let t = Instant::now();
    let m = measure_children(&target, MEASURE_DEFAULT_BUDGET);
    let bytes: u64 = m.children.iter().map(|c| c.size_bytes).sum();
    println!(
        "mesure {} : {} enfants, {:.2} Go, {:.0} ms ({} avert.)",
        target.display(),
        m.children.len(),
        bytes as f64 / 1e9,
        t.elapsed().as_secs_f64() * 1000.0,
        m.warnings.len()
    );

    let home = PathBuf::from(std::env::var("HOME").unwrap());
    let t = Instant::now();
    let large = find_large_files(&home, DEFAULT_MIN_BYTES, DEFAULT_LIMIT, Budget::new(DEFAULT_BUDGET), &Control::new());
    let bytes: u64 = large.files.iter().map(|f| f.size_bytes).sum();
    println!(
        "gros fichiers (≥ 50 Mio) : {} fichiers, {:.2} Go, {:.0} ms, complet : {}",
        large.files.len(),
        bytes as f64 / 1e9,
        t.elapsed().as_secs_f64() * 1000.0,
        large.complete
    );
    for f in large.files.iter().take(5) {
        println!("  {:>8.1} Mo  {}", f.size_bytes as f64 / 1e6, f.path.strip_prefix(&home).unwrap_or(&f.path).display());
    }

    let t = Instant::now();
    let dupes = find_duplicates(&home, maccare_core::dupes::DEFAULT_MIN_BYTES, Budget::new(maccare_core::dupes::DEFAULT_BUDGET), &Control::new());
    let reclaimable: u64 = dupes.groups.iter().map(|g| g.reclaimable()).sum();
    println!(
        "doublons (≥ 1 Mio) : {} groupes, {:.2} Go récupérables, {:.0} ms, complet : {}",
        dupes.groups.len(),
        reclaimable as f64 / 1e9,
        t.elapsed().as_secs_f64() * 1000.0,
        dupes.complete
    );
    for g in dupes.groups.iter().take(3) {
        println!("  {} × {:.1} Mo  {}", g.files.len(), g.length as f64 / 1e6, g.files[0].path.strip_prefix(&home).unwrap_or(&g.files[0].path).display());
    }
}
