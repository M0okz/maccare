#!/usr/bin/env bash
set -euo pipefail
# Pass a development (non-hardened) helper; never the installed application.
test_root="$(cd "$(dirname "$0")" && pwd)"
helper_path="${1:?Usage: run.sh /absolute/path/to/development/MacCareHelper}"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/maccare-diagnostics-cli.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT
xcrun clang -dynamiclib -Wall -Wextra -Werror -Wno-unused-parameter \
    -mmacosx-version-min=13.0 "$test_root/read-only-guard.c" \
    -framework IOKit -framework CoreFoundation -o "$work_root/guard.dylib"
python3 - "$helper_path" "$work_root/guard.dylib" "${2:-service}" <<'PY'
import json
import os
import subprocess
import sys

helper, guard, mode = sys.argv[1:]
assert mode in ('service', 'standalone')
env = dict(os.environ, DYLD_INSERT_LIBRARIES=guard)

def run(args, expected=0):
    result = subprocess.run([helper, *args], env=env, capture_output=True, text=True, timeout=20)
    assert 'read-only guard loaded' in result.stderr, result.stderr
    assert result.returncode == expected, (args, result.returncode, result.stderr)
    return result.stdout

full = json.loads(run(['--battery-full-diagnostics']))
assert full['method'] == 'read-only'
assert full['helperUID'] == os.geteuid()
assert 'percent' in full['snapshot']
assert 'fullChargeOverride' in full['compatibility']
rows = full['smc']
assert len(rows) == 40
assert len({(r['key'], r['transport'], r['handshake']) for r in rows}) == 40
assert {(r['transport'], r['handshake']) for r in rows if r['key'] == 'CHIE'} == {(0,0),(0,1),(1,0),(1,1)}
assert all(isinstance(r['result'], int) and len(r['bytes']) == 8 for r in rows)
legacy = json.loads(run(['--battery-diagnostics']))
assert 'supported' in legacy and 'snapshot' in legacy and 'smc' not in legacy
compatibility = json.loads(run(['--battery-compatibility-diagnostics']))
assert 'nativePolicyValidated' in compatibility and 'smc' not in compatibility
assert '--battery-full-diagnostics' in run(['--help'])
assert '--battery-full-diagnostics' in run(['-h'])
assert isinstance(json.loads(run(['--battery-build-info']))['m1MaxTrialBuild'], bool)
for args in [['--battery-full-diagnostic'], ['--unknown'],
             ['--battery-full-diagnostics', '--battery-diagnostics'],
             ['--battery-full-diagnostics', '--unknown']]:
    assert run(args, 2) == ''
if mode == 'standalone':
    assert run([], 2) == ''
print('CLI passed: full JSON, 40 SMC reads including CHIE, legacy formats, help, rejected arguments; side-effect guard active.')
PY
