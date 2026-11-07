#!/usr/bin/env python3
"""Construit le DMG signé et notarié ; ne publie rien sans réussite de tous les contrôles."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def notarize(path):
    if os.environ.get('MACCARE_NOTARY_KEY_FILE'):
        authentication = ['--key', os.environ['MACCARE_NOTARY_KEY_FILE'], '--key-id', os.environ['MACCARE_NOTARY_KEY_ID'],
                          '--issuer', os.environ['MACCARE_NOTARY_ISSUER_ID']]
    else:
        authentication = ['--apple-id', os.environ['MACCARE_APPLE_ID'], '--team-id', os.environ['MACCARE_APPLE_TEAM_ID'],
                          '--password', os.environ['MACCARE_NOTARY_PASSWORD']]
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(path), *authentication,
                             '--wait', '--timeout', '30m', '--output-format', 'json'], capture_output=True)
    if result.returncode:
        raise RuntimeError('Échec de notarisation Apple. Les arguments d’authentification ne sont pas journalisés.')
    status = json.loads(result.stdout)
    if status.get('status') != 'Accepted':
        raise RuntimeError(f'Notarisation refusée : {status.get("id")} ({status.get("status")}).')


def main():
    os.chdir(ROOT)
    if os.environ.get('MACCARE_DISTRIBUTION') != '1':
        raise SystemExit('MACCARE_DISTRIBUTION=1 est requis.')
    version = os.environ['MACCARE_VERSION']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Version invalide.')
    repository = os.environ['GITHUB_REPOSITORY']
    output = ROOT / 'build/release'
    output.mkdir(parents=True, exist_ok=True)
    app = output / 'MacCare.app'
    run('bash', 'app/package.sh', str(app))
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    for binary in ['MacOS/MacCare', 'MacOS/MacCareHelper', 'Helpers/mas']:
        arch = run('lipo', '-archs', str(app / 'Contents' / binary), capture_output=True, text=True).stdout.split()
        if arch != ['arm64']:
            raise RuntimeError('La distribution actuelle doit cibler uniquement Apple Silicon.')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    with tempfile.TemporaryDirectory(prefix='maccare-notary-', dir=output) as temporary:
        archive = Path(temporary) / 'MacCare.zip'
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
        notarize(archive)
    run('xcrun', 'stapler', 'staple', str(app))
    run('xcrun', 'stapler', 'validate', str(app))
    run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
    dmg = output / f'MacCare-{version}-arm64.dmg'
    run('bash', 'app/create-dmg.sh', '--skip-build', '--app', str(app), '--output', str(dmg))
    run('codesign', '--force', '--sign', os.environ['MACCARE_SIGN_IDENTITY'], '--timestamp', str(dmg))
    notarize(dmg)
    run('xcrun', 'stapler', 'staple', str(dmg))
    run('xcrun', 'stapler', 'validate', str(dmg))
    run('codesign', '--verify', '--strict', str(dmg))
    run('hdiutil', 'verify', str(dmg))
    # Contrôle du ticket sur le paquet réellement livré, et non uniquement sur celui d’avant copie.
    with tempfile.TemporaryDirectory(prefix='maccare-verify-', dir=output) as temporary:
        mount = Path(temporary) / 'mount'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg), stdout=subprocess.DEVNULL)
        try:
            run('codesign', '--verify', '--deep', '--strict', str(mount / 'MacCare.app'))
            run('xcrun', 'stapler', 'validate', str(mount / 'MacCare.app'))
        finally:
            run('hdiutil', 'detach', '-quiet', str(mount))
    # La signature Sparkle et le SHA-256 portent sur le DMG final, ticket compris.
    with dmg.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    dmg.with_suffix('.dmg.sha256').write_text(f'{digest}  {dmg.name}\n')
    run('python3', 'app/release/appcast.py', '--app', str(app), '--dmg', str(dmg),
        '--notes', os.environ['MACCARE_RELEASE_NOTES'], '--repository', repository,
        '--output', str(output / 'appcast.xml'),
        '--sign-tool', str(ROOT / 'app/.build/artifacts/sparkle/Sparkle/bin/sign_update'))
    (output / 'release.json').write_text(json.dumps({
        'version': version, 'build': info['CFBundleVersion'], 'architecture': 'arm64',
        'sha256': digest, 'sparkle': '2.10.1', 'notarized': True,
        'mas': json.loads((app / 'Contents/Resources/mas/manifest.json').read_text())['version'],
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
