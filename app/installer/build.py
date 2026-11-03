#!/usr/bin/env python3
"""Construit et contrôle un DMG natif, sans piloter le Finder ni installer l'app."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(*args: str, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main() -> None:
    if sys.version_info < (3, 11):
        raise SystemExit('La construction du DMG nécessite Python 3.11 ou ultérieur.')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true', help='Réutiliser les binaires release déjà construits')
    parser.add_argument('--output', type=Path, help='DMG de sortie, obligatoirement sous build/')
    parser.add_argument('--app', type=Path, help='Réutiliser un paquet signé et éventuellement agrafé, sous build/')
    args = parser.parse_args()
    os.chdir(ROOT)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    if args.app and not args.skip_build:
        parser.error('--app nécessite --skip-build pour préserver le paquet fourni.')
    if not args.skip_build:
        run('bash', str(ROOT / 'app/build.sh'))

    stage = Path(tempfile.mkdtemp(prefix='.installer-', dir=build))
    mounted: Path | None = None
    try:
        app = stage / 'MacCare.app'
        if args.app:
            supplied = args.app.resolve()
            if not supplied.is_relative_to(build.resolve()) or supplied.name != 'MacCare.app' or not supplied.is_dir():
                raise ValueError('Le paquet fourni doit être un MacCare.app existant sous build/.')
            run('codesign', '--verify', '--deep', '--strict', str(supplied))
            run('ditto', str(supplied), str(app))
        else:
            run('bash', str(ROOT / 'app/package.sh'), str(app))
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        version = info['CFBundleShortVersionString']
        architectures = run('lipo', '-archs', str(app / 'Contents/MacOS/MacCare'), capture_output=True, text=True).stdout.split()
        arch = 'universal' if set(architectures) == {'arm64', 'x86_64'} else '-'.join(architectures)
        destination = (args.output or build / f'MacCare-{version}-{arch}.dmg').resolve()
        if not destination.is_relative_to(build.resolve()) or destination.suffix != '.dmg':
            raise ValueError('Le DMG de sortie doit être placé sous build/ et porter l’extension .dmg.')
        destination.parent.mkdir(parents=True, exist_ok=True)

        # L'environnement d'outillage est isolé et nettoyé, sans paquet ajouté au Python global.
        tools = stage / 'tools'
        run(sys.executable, '-m', 'venv', str(tools))
        run(str(tools / 'bin/python'), '-m', 'pip', 'install', '--disable-pip-version-check',
            '--no-cache-dir', '-q', '-r', str(ROOT / 'app/installer/requirements.txt'))
        image = stage / 'MacCare.dmg'
        run(str(tools / 'bin/dmgbuild'), '-s', str(ROOT / 'app/installer/settings.py'),
            '-D', 'app=' + str(app), '-D', 'assets=' + str(build / 'installer-assets'), 'MacCare', str(image))

        # Vérifie le vrai contenu de l'image en lecture seule ; /Applications n'est jamais écrit.
        mountpoint = stage / 'verify-mount'
        mountpoint.mkdir()
        result = run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mountpoint),
                     '-plist', str(image), capture_output=True)
        attach = plistlib.loads(result.stdout)
        mounted = Path(next(entity['mount-point'] for entity in attach['system-entities'] if 'mount-point' in entity))
        bundled = mounted / 'MacCare.app'
        run('codesign', '--verify', '--deep', '--strict', str(bundled))
        run(str(tools / 'bin/python'), str(ROOT / 'app/installer/verify-layout.py'), str(mounted))
        copied = stage / 'copy-test' / 'MacCare.app'
        copied.parent.mkdir()
        run('ditto', str(bundled), str(copied))
        run('codesign', '--verify', '--deep', '--strict', str(copied))
        if not (mounted / 'Applications').is_symlink() or os.readlink(mounted / 'Applications') != '/Applications':
            raise RuntimeError('Le lien Applications ne vise pas /Applications.')
        if not (mounted / '.DS_Store').is_file() or not (bundled / 'Contents/Resources/MacCare.icns').is_file():
            raise RuntimeError('Métadonnées Finder ou icône absentes du DMG.')
        if not (bundled / 'Contents/MacOS/MacCareHelper').is_file():
            raise RuntimeError('Assistant privilégié absent du paquet.')
        run('hdiutil', 'detach', '-quiet', str(mounted))
        mounted = None

        # Le fichier final n'est remplacé qu'après la réussite de tous les contrôles.
        os.replace(image, destination)
        with destination.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        destination.with_suffix('.dmg.sha256').write_text(f'{digest}  {destination.name}\n')
        print(f'\nDMG vérifié : {destination}')
        print(f'Architecture : {arch} · version : {version}')
        print('Installation manuelle uniquement : aucune app copiée dans /Applications.')
        print('La diffusion exige Developer ID, un ticket de notarisation et une signature Sparkle vérifiés par la chaîne de release.')
    finally:
        if mounted is not None:
            try:
                run('hdiutil', 'detach', '-quiet', str(mounted))
                mounted = None
            except subprocess.CalledProcessError:
                print(f'Volume encore monté ; fichiers conservés pour diagnostic : {stage}', file=sys.stderr)
        if mounted is None:
            shutil.rmtree(stage)


if __name__ == '__main__':
    main()
