#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
qa_dir="$(mktemp -d "${TMPDIR:-/tmp}/maccare-no-developer-tools.XXXXXX")"
trap 'rm -rf "$qa_dir"' EXIT
sources=("$repo_root/app/Sources/MacCare/AppCatalog.swift" "$repo_root/app/Sources/MacCare/ApplicationInsights.swift" "$repo_root/app/Tests/NoDeveloperToolsTests/ScannerCanary.swift")
if [ -f "$repo_root/app/Sources/MacCare/ExecutableArchitectures.swift" ]; then
    sources+=("$repo_root/app/Sources/MacCare/ExecutableArchitectures.swift")
fi
swiftc -parse-as-library -target "$(uname -m)-apple-macos13.0" "${sources[@]}" -o "$qa_dir/scanner-canary"
"$qa_dir/scanner-canary" "$qa_dir/fixtures" "$@"

# This architectural guard also covers future runtime consumers, including
# update staging. Build/release scripts may still use the developer toolchain.
python3 - "$repo_root/app/Sources" "$repo_root/core/src" <<'PY'
from pathlib import Path
import re,sys
tools = {
    'ar', 'as', 'bison', 'c++', 'c89', 'c99', 'cc', 'clang', 'clang++',
    'codesign_allocate', 'cpp', 'ctags', 'ctf_insert', 'dsymutil', 'dwarfdump',
    'dyldinfo', 'flex', 'g++', 'gcc', 'gcov', 'git', 'gnumake', 'gperf',
    'install_name_tool', 'ld', 'lex', 'libtool', 'lipo', 'llvm-cov',
    'llvm-dwarfdump', 'llvm-objdump', 'llvm-otool', 'llvm-profdata', 'llvm-size',
    'm4', 'make', 'mig', 'nm', 'nmedit', 'objdump', 'otool', 'pagestuff',
    'ranlib', 'size', 'strings', 'strip', 'swift', 'swiftc', 'unifdef', 'vtool',
    'xcodebuild', 'xcrun', 'yacc',
}
pattern = re.compile(r'["\x27]/usr/bin/(?:' + '|'.join(re.escape(t) for t in sorted(tools)) + r')["\x27]')
locate = re.compile(r'(?:SystemTools\.locate|Command::new)\(\s*["\x27](?:' + '|'.join(re.escape(t) for t in sorted(tools)) + r')["\x27]')
violations=[]
for root in map(Path, sys.argv[1:]):
    for path in sorted(root.rglob('*')):
        if path.is_file() and path.suffix in {'.swift','.c','.h','.m','.mm','.cpp','.rs'}:
            text = path.read_text()
            # xcode-select -p is a safe OS query used by the optional simulator
            # feature; only its installer action is forbidden here.
            if 'xcode-select' in text and re.search(r'["\x27]--install["\x27]', text):
                violations.append(f'{root.name}/{path.relative_to(root)}: developer-tools installer request')
            for number,line in enumerate(text.splitlines(),1):
                if pattern.search(line) or locate.search(line):violations.append(f'{root.name}/{path.relative_to(root)}:{number}: {line.strip()}')
if violations:raise SystemExit('FAIL: runtime dependency on a developer-tool shim:\n'+'\n'.join(violations))
print('PASS: runtime sources contain no direct developer-tool shim dependency')
PY
