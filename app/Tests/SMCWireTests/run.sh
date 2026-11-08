#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd "$(dirname "$0")" && pwd)"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/maccare-smc-tests.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT
xcrun clang -Wall -Wextra -Werror -Wno-unused-parameter -Wno-sign-compare \
    -fsanitize=address,undefined -fno-sanitize-recover=all -O1 -g \
    -mmacosx-version-min=13.0 \
    -I"$test_root/../../Sources/CMacCareSMC/include" \
    "$test_root/main.c" -framework IOKit -framework CoreFoundation \
    -o "$work_root/SMCWireTests"
"$work_root/SMCWireTests"
