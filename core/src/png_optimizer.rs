//! PNG copies: bounded input, lossless options, exclusive output creation, no original writes.
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, MetadataExt};
use std::path::Path;
use std::time::Duration;

const MAX_BYTES: u64 = 64 * 1024 * 1024;
const MAX_PIXELS: u64 = 32 * 1024 * 1024;

#[derive(Debug, Serialize)]
pub struct OptimizedPNG {
    pub original_bytes: u64,
    pub optimized_bytes: u64,
    pub output_path: Option<String>,
}

pub fn optimize_copy(source: &Path, directory: &Path) -> Result<OptimizedPNG, String> {
    if !source.is_absolute() || !directory.is_absolute() {
        return Err("Choisissez une image et un dossier de destination.".into());
    }
    if !source.extension().is_some_and(|s| s.eq_ignore_ascii_case("png")) {
        return Err("Choisissez une image au format PNG.".into());
    }
    let file = OpenOptions::new().read(true).custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(source).map_err(|_| "Cette image n’est pas accessible.".to_string())?;
    let metadata = file.metadata().map_err(|_| "Impossible de lire cette image.".to_string())?;
    if !metadata.is_file() || metadata.len() > MAX_BYTES {
        return Err("Choisissez un PNG de 64 Mo maximum.".into());
    }
    let mut data = Vec::new();
    file.take(MAX_BYTES + 1).read_to_end(&mut data).map_err(|_| "Lecture de l’image interrompue.".to_string())?;
    if data.len() as u64 > MAX_BYTES || data.len() < 33 || &data[..8] != b"\x89PNG\r\n\x1a\n" || &data[12..16] != b"IHDR" {
        return Err("Ce fichier n’est pas un PNG pris en charge.".into());
    }
    let width = u32::from_be_bytes(data[16..20].try_into().unwrap()) as u64;
    let height = u32::from_be_bytes(data[20..24].try_into().unwrap()) as u64;
    if width == 0 || height == 0 || width * height > MAX_PIXELS {
        return Err("Cette image dépasse la limite de 32 mégapixels.".into());
    }
    // Animated PNGs can multiply decoded memory/work across frames; this tool handles still PNGs.
    let mut offset = 8usize;
    while offset + 12 <= data.len() {
        let length = u32::from_be_bytes(data[offset..offset + 4].try_into().unwrap()) as usize;
        if &data[offset + 4..offset + 8] == b"acTL" {
            return Err("Les PNG animés ne sont pas encore pris en charge. L’original est conservé.".into());
        }
        match offset.checked_add(length).and_then(|end| end.checked_add(12)) {
            Some(end) if end <= data.len() => offset = end,
            _ => break,
        }
    }
    // Keep chunks, color representation and hidden RGB values; only recompress image data.
    let mut options = oxipng::Options::from_preset(2);
    options.timeout = Some(Duration::from_secs(15));
    options.max_decompressed_size = Some(256 * 1024 * 1024);
    options.optimize_alpha = false;
    options.bit_depth_reduction = false;
    options.color_type_reduction = false;
    options.palette_reduction = false;
    options.grayscale_reduction = false;
    options.interlace = None;
    let optimized = oxipng::optimize_from_memory(&data, &options)
        .map_err(|_| "Ce PNG ne peut pas être allégé. L’original est conservé.".to_string())?;
    let mut result = OptimizedPNG { original_bytes: data.len() as u64, optimized_bytes: data.len() as u64, output_path: None };
    if optimized.len() >= data.len() { return Ok(result); }
    let destination = fs::canonicalize(directory).map_err(|_| "Le dossier de destination est inaccessible.".to_string())?;
    if !destination.is_dir() { return Err("Choisissez un dossier de destination.".into()); }
    let raw_stem = source.file_stem().and_then(|s| s.to_str()).unwrap_or("Image");
    let stem: String = raw_stem.chars().scan(0, |bytes, c| {
        *bytes += c.len_utf8(); if *bytes <= 160 { Some(c) } else { None }
    }).collect();
    for index in 1..=1000 {
        let suffix = if index == 1 { String::new() } else { format!(" {index}") };
        let output = destination.join(format!("{stem} — optimisé{suffix}.png"));
        let mut created = match OpenOptions::new().write(true).create_new(true).mode(0o600).open(&output) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return Err("Impossible d’enregistrer une copie dans ce dossier.".into()),
        };
        if created.write_all(&optimized).and_then(|_| created.sync_all()).is_err() {
            if let (Ok(opened), Ok(current)) = (created.metadata(), fs::symlink_metadata(&output)) {
                if opened.dev() == current.dev() && opened.ino() == current.ino() { let _ = fs::remove_file(&output); }
            }
            return Err("Enregistrement interrompu. L’original est conservé.".into());
        }
        result.optimized_bytes = optimized.len() as u64;
        result.output_path = Some(output.to_string_lossy().into_owned());
        return Ok(result);
    }
    Err("Trop de copies existent déjà dans ce dossier.".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    const FIXTURE: &[u8] = include_bytes!("../tests/fixtures/repetitive.png");

    #[test]
    fn optimizes_only_new_copies_and_preserves_existing_files_and_metadata() {
        let dir = tempdir().unwrap();
        let input = dir.path().join("Photo.png");
        fs::write(&input, FIXTURE).unwrap();
        let old = dir.path().join("Photo — optimisé.png");
        fs::write(&old, b"existing file").unwrap();
        let result = optimize_copy(&input, dir.path()).unwrap();
        assert!(result.optimized_bytes < result.original_bytes);
        assert_eq!(fs::read(&input).unwrap(), FIXTURE);
        assert_eq!(fs::read(&old).unwrap(), b"existing file");
        let output = result.output_path.unwrap();
        assert!(output.ends_with("optimisé 2.png"));
        let bytes = fs::read(output).unwrap();
        assert!(bytes.windows(b"MacCare fixture".len()).any(|w| w == b"MacCare fixture"));
        assert_eq!(&bytes[16..26], &FIXTURE[16..26]);
    }

    #[test]
    fn refuses_symlinks_invalid_files_and_excessive_dimensions() {
        let dir = tempdir().unwrap();
        let input = dir.path().join("Photo.png");
        fs::write(&input, FIXTURE).unwrap();
        let link = dir.path().join("Link.png");
        std::os::unix::fs::symlink(&input, &link).unwrap();
        assert!(optimize_copy(&link, dir.path()).is_err());
        fs::write(&input, b"not png").unwrap();
        assert!(optimize_copy(&input, dir.path()).is_err());
        let mut large = FIXTURE.to_vec();
        large[16..20].copy_from_slice(&100000u32.to_be_bytes());
        fs::write(&input, large).unwrap();
        assert!(optimize_copy(&input, dir.path()).is_err());
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
    }

    #[test]
    fn refuses_animated_png_before_decoding_multiple_frames() {
        let dir = tempdir().unwrap();
        let input = dir.path().join("Animation.png");
        let mut data = FIXTURE.to_vec();
        let chunk = [0, 0, 0, 8, b'a', b'c', b'T', b'L', 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0];
        data.splice(33..33, chunk);
        fs::write(&input, &data).unwrap();
        assert!(optimize_copy(&input, dir.path()).unwrap_err().contains("animés"));
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
        assert_eq!(fs::read(input).unwrap(), data);
    }

    #[test]
    fn never_creates_a_larger_copy_for_an_already_optimized_png() {
        let dir = tempdir().unwrap();
        let input = dir.path().join("Photo.png");
        fs::write(&input, FIXTURE).unwrap();
        let first = optimize_copy(&input, dir.path()).unwrap();
        let second = optimize_copy(Path::new(&first.output_path.unwrap()), dir.path()).unwrap();
        assert!(second.optimized_bytes <= second.original_bytes);
        if second.optimized_bytes == second.original_bytes { assert!(second.output_path.is_none()); }
    }
}
