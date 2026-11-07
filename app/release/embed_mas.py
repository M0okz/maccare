#!/usr/bin/env python3
"""Embarque le Mach-O officiel de mas, sans exécuter son installateur ni Homebrew."""
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

VENDOR = Path(__file__).resolve().parents[1] / 'vendor/mas'


def verify_archive(path, expected):
    with path.open('rb') as source:
        actual = hashlib.file_digest(source, 'sha256').hexdigest()
    if actual != expected:
        raise ValueError('Empreinte SHA-256 incorrecte pour mas ; assemblage interrompu.')


def validate_binary(binary, architecture):
    archs = subprocess.check_output(['/usr/bin/lipo', '-archs', str(binary)], text=True).split()
    if archs != [architecture]:
        raise ValueError('Architecture mas incompatible avec MacCare.')
    headers = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
    minimums = re.findall(r'^\s*minos\s+(\d+(?:\.\d+){0,2})\s*$', headers, re.MULTILINE)
    if not minimums or any(tuple(map(int, value.split('.'))) > (13, 0, 0) for value in minimums):
        raise ValueError('mas doit rester compatible avec macOS 13.')
    libraries = subprocess.check_output(['/usr/bin/otool', '-L', str(binary)], text=True)
    for line in libraries.splitlines()[1:]:
        library = line.strip().split(' (', 1)[0]
        if not library.startswith(('/usr/lib/', '/System/Library/')):
            raise ValueError('Dépendance mas externe au système : ' + library)


def embed(app, architecture=None):
    architecture = architecture or platform.machine()
    manifest = json.loads((VENDOR / 'manifest.json').read_text())
    if architecture not in manifest['archives']:
        raise ValueError('Architecture mas non prise en charge : ' + architecture)
    archive = manifest['archives'][architecture]
    # Les téléchargements et le contenu de l'installateur restent temporaires.
    with tempfile.TemporaryDirectory(prefix='maccare-mas-') as temporary:
        work = Path(temporary)
        package = work / 'mas.pkg'
        with urllib.request.urlopen(archive['url'], timeout=60) as response, package.open('wb') as destination:
            shutil.copyfileobj(response, destination)
        verify_archive(package, archive['sha256'])
        expanded = work / 'expanded'
        subprocess.run(['/usr/sbin/pkgutil', '--expand-full', str(package), str(expanded)], check=True)
        payload = expanded / 'mas.pkg/Payload/usr/local/opt/mas'
        binary = payload / 'libexec/bin/mas'
        validate_binary(binary, architecture)
        if (payload / 'LICENSE').read_bytes() != (VENDOR / 'LICENSE').read_bytes():
            raise ValueError('La licence mas ne correspond pas à la version figée.')
        target = app / 'Contents/Helpers/mas'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(binary, target)
        target.chmod(0o755)
        notices = app / 'Contents/Resources/mas'
        shutil.copytree(VENDOR, notices, dirs_exist_ok=True)
    print(f'==> mas {manifest["version"]} ({architecture}) embarqué et vérifié, sans Homebrew')


if __name__ == '__main__':
    embed(Path(sys.argv[1]))
