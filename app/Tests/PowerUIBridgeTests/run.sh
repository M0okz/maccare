#!/usr/bin/env bash
set -euo pipefail
test_root="$(cd "$(dirname "$0")" && pwd)"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/maccare-powerui-tests.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -fsanitize=address,undefined -fno-sanitize-recover=all -O1 -g \
    -mmacosx-version-min=13.0 \
    -I"$test_root/../../Sources/CMacCarePowerUI/include" \
    "$test_root/main.m" -framework Foundation -framework CoreFoundation \
    -o "$work_root/PowerUIBoundaryTests"
"$work_root/PowerUIBoundaryTests"
