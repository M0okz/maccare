#!/usr/bin/env bash
# Génère le DMG glisser-déposer, après construction et signature du paquet.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$repo_root/app/installer/build.py" "$@"
