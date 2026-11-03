#!/usr/bin/env python3
"""Importe les secrets CI uniquement dans un trousseau éphémère du runner."""
import base64
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys

NAMES = (
    'MACCARE_CERTIFICATE_P12',
    'MACCARE_CERTIFICATE_PASSWORD',
    'MACCARE_NOTARY_KEY_P8',
    'MACCARE_NOTARY_KEY_ID',
    'MACCARE_NOTARY_ISSUER_ID',
    'MACCARE_SPARKLE_PRIVATE_KEY',
    'MACCARE_SPARKLE_PUBLIC_KEY',
)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def main():
    directory = Path(os.environ['RUNNER_TEMP']) / 'maccare-signing'
    if sys.argv[1:] == ['cleanup']:
        keychain = directory / 'signing.keychain-db'
        if keychain.exists():
            run('security', 'delete-keychain', str(keychain))
        if directory.exists():
            for file in directory.iterdir():
                file.unlink()
            directory.rmdir()
        return
    missing = [name for name in NAMES if not os.environ.get(name)]
    if missing:
        raise SystemExit('Configuration de release manquante : ' + ', '.join(missing))
    run('swift', str(Path(__file__).with_name('validate-sparkle-key.swift')), os.environ['MACCARE_SPARKLE_PUBLIC_KEY'],
        input=os.environ['MACCARE_SPARKLE_PRIVATE_KEY'].encode())
    directory.mkdir(mode=0o700)
    certificate = directory / 'certificate.p12'
    notary = directory / 'AuthKey.p8'
    certificate.write_bytes(base64.b64decode(os.environ['MACCARE_CERTIFICATE_P12'], validate=True))
    certificate.chmod(0o600)
    notary.write_text(os.environ['MACCARE_NOTARY_KEY_P8'])
    notary.chmod(0o600)
    password = secrets.token_urlsafe(32)
    keychain = directory / 'signing.keychain-db'
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(certificate), '-P', os.environ['MACCARE_CERTIFICATE_PASSWORD'],
        '-T', '/usr/bin/codesign', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
    previous = run('security', 'list-keychains', '-d', 'user').stdout.decode()
    # Le runner est éphémère ; les trousseaux préexistants restent dans la liste de recherche.
    existing = re.findall(r'"([^"]+)"', previous)
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *existing)
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)).stdout.decode()
    identity = re.search(r'([A-F0-9]{40}) "Developer ID Application:', identities)
    if not identity:
        raise SystemExit('Le certificat importé ne contient pas de Developer ID Application valide.')
    certificate.unlink()
    with Path(os.environ['GITHUB_ENV']).open('a') as env:
        env.write(f'MACCARE_SIGN_IDENTITY={identity[1]}\nMACCARE_NOTARY_KEY_FILE={notary}\n')
    print('Identité Developer ID et clé de notarisation disponibles pour ce runner uniquement.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError:
        raise SystemExit('Échec de préparation du trousseau de signature ; aucune valeur secrète affichée.')
