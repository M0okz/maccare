#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
test_bin="$(mktemp -t maccare-device-battery-tests)"
trap 'rm -f "$test_bin"' EXIT
xcrun clang -fobjc-arc -framework Foundation -fsanitize=address,undefined -g \
    "$test_dir/main.m" -o "$test_bin"
"$test_bin"
