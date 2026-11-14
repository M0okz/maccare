#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
qa_dir="$(mktemp -d "${TMPDIR:-/tmp}/maccare-toolbar-lifecycle.XXXXXX")"
trap 'rm -rf "$qa_dir"' EXIT
probe_app="$qa_dir/ToolbarProbe.app"
mkdir -p "$probe_app/Contents/MacOS"
python3 - "$probe_app" <<'PY'
from pathlib import Path
import plistlib,sys,uuid
root=Path(sys.argv[1])/'Contents'
plistlib.dump({'CFBundleIdentifier':'org.maccare.toolbar-regression-probe.'+uuid.uuid4().hex,'CFBundleName':'MacCare Toolbar Probe','CFBundleExecutable':'ToolbarProbe','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'13.0'},(root/'Info.plist').open('wb'))
PY
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    "$repo_root/app/Sources/MacCare/AboutView.swift" \
    "$repo_root/app/Sources/MacCare/AboutReleaseNotesView.swift" \
    "$repo_root/app/Sources/MacCare/AboutSidebarButton.swift" \
    "$repo_root/app/Sources/MacCare/SidebarRowStyle.swift" \
    "$repo_root/app/Sources/MacCare/DesignSystem.swift" \
    "$repo_root/app/Sources/MacCare/Motion.swift" \
    "$repo_root/app/Sources/MacCare/AppBuildIdentity.swift" \
    "$repo_root/app/Sources/MacCare/MainWindowLayout.swift" \
    "$repo_root/app/Sources/MacCare/MainWindowDisplayObserver.swift" \
    "$repo_root/app/Sources/MacCare/WindowConfigurator.swift" \
    "$repo_root/app/Tests/WindowToolbarLifecycleTests/ToolbarLifecycleProbe.swift" \
    -o "$probe_app/Contents/MacOS/ToolbarProbe"
if [[ "${1:-}" == "--compile-only" ]]; then
    echo "PASS: shipping About view and window configurator compiled in the isolated lifecycle probe"
    exit 0
fi
# An active WindowServer session is required. No app scan, download or installation is performed.
python3 - "$probe_app/Contents/MacOS/ToolbarProbe" <<'PY'
import os,subprocess,sys
for run in range(4):
    env=os.environ.copy();env['MACCARE_TOOLBAR_QA_START_VISIBLE']=str(run%2)
    result=subprocess.run([sys.argv[1]],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=35)
    print(result.stdout,flush=True)
    if result.returncode or 'TOOLBAR_PROBE completed=160' not in result.stdout:
        raise SystemExit(f'FAIL: lifecycle run {run+1}, exit {result.returncode}')
print('PASS: four launches and 640 availability transitions, no toolbar exception')
PY
