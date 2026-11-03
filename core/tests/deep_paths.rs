//! Arborescences plus profondes que `PATH_MAX` (1 024 octets) : le parcours les mesure quand même.

use maccare_core::walk::{measure_path, walk_paths, Budget, Control, WalkOptions};
use std::ffi::CString;
use std::time::Duration;

/// Crée, à partir de `base`, `depth` dossiers imbriqués de nom `segment`, puis un fichier de
/// `bytes` octets au fond. Tout passe par des descripteurs (`mkdirat`/`openat`) : un chemin absolu
/// aussi long serait refusé par le système. Renvoie l'espace alloué du fichier.
fn deep_tree(base: &std::path::Path, segment: &str, depth: usize, bytes: usize) -> u64 {
    unsafe {
        let b = CString::new(base.to_str().unwrap()).unwrap();
        let mut fd = libc::open(b.as_ptr(), libc::O_RDONLY | libc::O_DIRECTORY);
        assert!(fd >= 0);
        let name = CString::new(segment).unwrap();
        for _ in 0..depth {
            assert_eq!(libc::mkdirat(fd, name.as_ptr(), 0o755), 0);
            let next = libc::openat(fd, name.as_ptr(), libc::O_RDONLY | libc::O_DIRECTORY);
            assert!(next >= 0);
            libc::close(fd);
            fd = next;
        }
        let file = CString::new("fond.bin").unwrap();
        let f = libc::openat(fd, file.as_ptr(), libc::O_CREAT | libc::O_WRONLY, 0o644);
        assert!(f >= 0);
        let data = vec![7u8; bytes];
        assert_eq!(libc::write(f, data.as_ptr() as *const _, data.len()), data.len() as isize);
        let mut st: libc::stat = std::mem::zeroed();
        assert_eq!(libc::fstat(f, &mut st), 0);
        libc::close(f);
        libc::close(fd);
        st.st_blocks as u64 * 512
    }
}

#[test]
fn measures_trees_deeper_than_path_max() {
    let tmp = tempfile::tempdir().unwrap();
    let base = tmp.path().canonicalize().unwrap();
    let segment = "dossier-au-nom-assez-long-pour-depasser-path-max";
    // ~30 niveaux de 49 caractères : plus de 1 500 octets de chemin.
    let alloc = deep_tree(&base, segment, 30, 200_000);
    assert!(base.to_str().unwrap().len() + 30 * (segment.len() + 1) > 1024);

    let m = measure_path(&base, Budget::new(Duration::from_secs(30)));
    assert!(m.complete);
    assert_eq!(m.bytes, alloc, "le fichier au fond est compté");

    // La collecte (gros fichiers, doublons) le trouve aussi, avec son chemin complet.
    let found = walk_paths(
        std::slice::from_ref(&base),
        Budget::new(Duration::from_secs(30)),
        &Control::new(),
        WalkOptions { collect_min: Some(1), ..Default::default() },
    )
    .found;
    assert_eq!(found.len(), 1);
    assert!(found[0].path.as_os_str().len() > 1024);
    assert!(found[0].path.ends_with("fond.bin"));
}
