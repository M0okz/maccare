#!/bin/bash
set -euo pipefail
test_dir="$(cd "$(dirname "$0")" && pwd)"
test_work="$(mktemp -d -t maccare-device-battery-tests)"
trap 'rm -rf "$test_work"' EXIT
test_bin="$test_work/probe-tests"
xcrun clang -fobjc-arc -framework Foundation -fsanitize=address,undefined -g \
    "$test_dir/main.m" -o "$test_bin"
"$test_bin"
