#!/usr/bin/env python3
"""Extract App Intents into the manually assembled signed macOS bundle."""
import argparse
from pathlib import Path
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('bundle', type=Path)
parser.add_argument('--configuration', choices=('Debug', 'Release'), default='Release')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
bundle = args.bundle.resolve()
if not bundle.is_relative_to(root / 'build'):
    raise SystemExit('Bundle output must be inside build/.')
const_files = list((root/'app/.build/out/Intermediates.noindex/MacCare.build'/args.configuration).glob('MacCare-p.build/Objects-normal/*/*.swiftconstvalues'))
if not const_files:
    raise SystemExit('Missing App Intents constant metadata. Build MacCare before packaging.')
preferred = platform.machine()
const_file = next((p for p in const_files if p.parent.name == preferred), const_files[0])
arch = const_file.parent.name
const_files = [p for p in const_files if p.parent.name == arch]
sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
toolchain = Path(subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()).parents[2]
xcode_version = subprocess.check_output(['xcodebuild','-version'],text=True).strip().splitlines()[-1].split()[-1]
output = bundle/'Contents/Resources'
output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='maccare-intents-') as work:
    work = Path(work)
    sources = work/'sources.txt'; values = work/'constants.txt'
    sources.write_text('\n'.join(str(p) for p in (root/'app/Sources/MacCare').glob('*.swift'))+'\n')
    values.write_text('\n'.join(str(p) for p in const_files)+'\n')
    subprocess.run(['xcrun','appintentsmetadataprocessor','--output',str(output),
                    '--toolchain-dir',str(toolchain),'--module-name','MacCare','--sdk-root',sdk,
                    '--xcode-version',xcode_version,'--platform-family','macOS','--deployment-target','13.0',
                    '--target-triple',arch+'-apple-macos13.0','--source-file-list',str(sources),
                    '--swift-const-vals-list',str(values)],check=True)
metadata = output/'Metadata.appintents'
if not metadata.is_dir() or not any(metadata.iterdir()):
    raise SystemExit('App Intents metadata was not produced.')
print('App Intents metadata verified:',metadata)

required = ('SetBatteryLimitIntent', 'TopUpBatteryIntent', 'StopBatteryProtectionIntent', 'StartBatteryCycleIntent')
payload = b''.join(p.read_bytes() for p in metadata.iterdir() if p.is_file())
if any(name.encode() not in payload for name in required):
    raise SystemExit('One or more battery actions are missing from App Intents metadata.')
