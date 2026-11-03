#!/usr/bin/env bash
# Construit le moteur Rust (staticlib) puis l'app SwiftUI liée dessus.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo "==> Build moteur Rust (staticlib)"
# La std du Rust Homebrew local est compilée pour macOS 26. Abaisser seulement
# MACOSX_DEPLOYMENT_TARGET ne la recompile pas et casse ici les proc-macros.
# Les composants officiels conservent leur minimum macOS 11 sur Apple Silicon.
case "$(uname -m)" in
    arm64) rust_target="aarch64-apple-darwin" ;;
    x86_64) rust_target="x86_64-apple-darwin" ;;
    *) echo "Architecture de build macOS non prise en charge." >&2; exit 1 ;;
esac
rust_toolchain="${MACCARE_RUST_TOOLCHAIN:-$repo_root/build/toolchains/rust-1.98.1}"
if [ -z "${MACCARE_RUST_TOOLCHAIN:-}" ] && [ ! -x "$rust_toolchain/bin/rustc" ]; then
    echo "==> Préparation de Rust officiel 1.98.1 dans build/toolchains/"
    python3 - "$rust_toolchain" "$rust_target" <<'PYCODE'
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile

prefix = Path(sys.argv[1]).resolve()
target = sys.argv[2]
# Sources et empreintes du manifeste officiel du 3 septembre 2026 :
# https://static.rust-lang.org/dist/channel-rust-1.98.1.toml
manifest_hash = "a7c8774a5fd8441c997d94c029776cbc5eb111e9d72ab5d256fa69866644347e"
hashes = {
    "aarch64-apple-darwin": {
        "rustc": "738e3f60114b20550fcf4f8a57c9cea0544239f214709f45594ff3fde327f577",
        "cargo": "de51d4fade4f31ad8ec405261cc96bedc000d905f98980027610d6e288dbe21b",
        "rust-std": "2de831ef563ce772519a4d18ba2659f0f7428d497ef66dad24b5a35e8f8cd177",
    },
    "x86_64-apple-darwin": {
        "rustc": "641c301bd19c3cead114cbb61919c5ed2475ce53e2d011fe0c990e16c5a1b04b",
        "cargo": "74b1282253c31fb89926d51d57e47a06c6cd26c93657de72edf622a4ab66396f",
        "rust-std": "48b9835058a8baa4ff5e4387f3772c572a017a2b13393c46e151615c54e322e9",
    },
}[target]
if prefix.exists():
    raise SystemExit("Le répertoire de chaîne existe mais est incomplet : " + str(prefix))
prefix.parent.mkdir(parents=True, exist_ok=True)
prefix.mkdir()
try:
    with tempfile.TemporaryDirectory(prefix="maccare-rust-download-") as temporary:
        work = Path(temporary)
        for component, expected in hashes.items():
            name = component + "-1.98.1-" + target
            archive = work / (name + ".tar.xz")
            url = "https://static.rust-lang.org/dist/2026-09-03/" + archive.name
            subprocess.run(["curl", "-fL", "--retry", "2", "--silent", "--show-error", url, "-o", str(archive)], check=True)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
                raise RuntimeError("Empreinte officielle incorrecte : " + component)
            subprocess.run(["tar", "-xJf", str(archive), "-C", str(work)], check=True)
            subprocess.run(["sh", str(work / name / "install.sh"), "--prefix=" + str(prefix), "--disable-ldconfig"], check=True)
        (prefix / "maccare-source.json").write_text(json.dumps({
            "version": "1.98.1", "target": target,
            "manifest_url": "https://static.rust-lang.org/dist/channel-rust-1.98.1.toml",
            "manifest_sha256": manifest_hash, "component_sha256": hashes,
        }, indent=2) + "\n")
except BaseException:
    shutil.rmtree(prefix)
    raise
PYCODE
fi
if [ ! -x "$rust_toolchain/bin/rustc" ] || [ ! -x "$rust_toolchain/bin/cargo" ]; then
    echo "MACCARE_RUST_TOOLCHAIN doit désigner un répertoire contenant bin/rustc et bin/cargo." >&2
    exit 1
fi
rust_toolchain="$(cd "$rust_toolchain" && pwd)"
RUSTC="$rust_toolchain/bin/rustc" MACOSX_DEPLOYMENT_TARGET=13.0 \
    "$rust_toolchain/bin/cargo" build --locked --release --manifest-path core/Cargo.toml \
        --target "$rust_target" --target-dir "$repo_root/core/target"

rust_archive="$repo_root/core/target/$rust_target/release/libmaccare_core.a"
python3 - "$rust_archive" <<'PYCODE'
import re
import subprocess
import sys

headers = subprocess.check_output(["xcrun", "llvm-objdump", "--macho", "--private-headers", sys.argv[1]], text=True)
versions = []
kind = None
for line in headers.splitlines():
    if re.match(r"\s*cmd\s+", line):
        kind = line.split()[-1]
    match = re.match(r"\s*(minos|version)\s+(\d+(?:\.\d+){0,2})\s*$", line)
    if match and ((kind == "LC_BUILD_VERSION" and match[1] == "minos") or
                  (kind == "LC_VERSION_MIN_MACOSX" and match[1] == "version")):
        value = tuple(int(part) for part in match[2].split("."))
        versions.append(value + (0,) * (3 - len(value)))
if not versions or max(versions) > (13, 0, 0):
    raise SystemExit("La bibliothèque Rust contient des objets exigeant une version supérieure à macOS 13. Utilisez une chaîne officielle compatible via MACCARE_RUST_TOOLCHAIN.")
print("==> Minimum macOS des objets Rust vérifié (13 ou antérieur)")
PYCODE
# Conserve le chemin de liaison partagé par les commandes Swift et les tests.
mkdir -p "$repo_root/core/target/release"
cp "$rust_archive" "$repo_root/core/target/release/libmaccare_core.a"

echo "==> Synchronisation de l'en-tête C"
cp core/include/maccare_core.h app/Sources/CMacCareCore/include/maccare_core.h

echo "==> Build app SwiftUI"
swift build --package-path app -c release \
    -Xlinker -L"$repo_root/core/target/release"

bin="app/.build/release/MacCare"
echo "==> OK : $bin"
echo "    Lancer avec : $bin"
