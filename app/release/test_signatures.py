#!/usr/bin/env python3
"""Contrôles cryptographiques isolés, avec une paire de clés temporaire jamais persistée."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    pair = subprocess.check_output(['swift', '-e', '''
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
'''], text=True).splitlines()
    environment = dict(os.environ, MACCARE_SPARKLE_PRIVATE_KEY=pair[0])
    validator = str(ROOT / 'app/release/validate-sparkle-key.swift')
    subprocess.run(['swift', validator, pair[1]], input=pair[0], text=True, check=True)
    wrong_key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
    if subprocess.run(['swift', validator, wrong_key], input=pair[0], text=True,
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise RuntimeError('Une paire de clés incohérente a été acceptée.')
    tool = str(ROOT / 'app/.build/artifacts/sparkle/Sparkle/bin/sign_update')
    with tempfile.TemporaryDirectory(prefix='maccare-signatures-') as temporary:
        directory = Path(temporary)
        app = directory / 'MacCare.app'
        (app / 'Contents').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '42', 'SUPublicEDKey': pair[1],
        }))
        dmg = directory / 'MacCare-0.1.0-arm64.dmg'
        dmg.write_bytes(b'Isolated test archive, no application or personal files.')
        notes = directory / 'notes.txt'
        notes.write_text('Test de signature, aucune publication.')
        feed = directory / 'appcast.xml'
        subprocess.run(['python3', str(ROOT / 'app/release/appcast.py'), '--app', str(app), '--dmg', str(dmg),
                        '--notes', str(notes), '--repository', 'M0okz/maccare', '--output', str(feed),
                        '--sign-tool', tool], env=environment, check=True)
        feed.write_bytes(feed.read_bytes().replace(b'0.1.0', b'0.1.1'))
        tampered = subprocess.run([tool, '--ed-key-file', '-', '--verify', str(feed)], input=pair[0], text=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if tampered.returncode == 0:
            raise RuntimeError('Un flux modifié après signature a été accepté.')
    print('Signatures Sparkle validées ; clé incohérente et flux altéré refusés. Aucun secret conservé.')


if __name__ == '__main__':
    main()
