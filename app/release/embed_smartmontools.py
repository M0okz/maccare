"""Bundle only smartctl, its drive database and corresponding GPL source; never install smartd."""
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request

from app.release.embed_mas import verify_archive, validate_binary

VENDOR = Path(__file__).resolve().parents[1] / 'vendor/smartmontools'


def download(record, path):
    with urllib.request.urlopen(record['url'], timeout=60) as response, path.open('wb') as destination:
        shutil.copyfileobj(response, destination)
    verify_archive(path, record['sha256'])


def embed(app, architecture=None):
    architecture = architecture or platform.machine()
    if architecture not in ('arm64', 'x86_64'):
        raise ValueError('Architecture non prise en charge.')
    manifest = json.loads((VENDOR / 'manifest.json').read_text())
    with tempfile.TemporaryDirectory(prefix='maccare-smartctl-') as temporary:
        work = Path(temporary)
        dmg = work / 'smartmontools.dmg'
        download(manifest['dmg'], dmg)
        source = work / 'smartmontools-source.tar.gz'
        download(manifest['source'], source)
        mount = work / 'mount'
        mount.mkdir()
        subprocess.run(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
        try:
            expanded = work / 'expanded'
            subprocess.run(['/usr/sbin/pkgutil', '--expand-full', str(mount / 'smartmontools-7.5-r5714.pkg'), str(expanded)], check=True)
        finally:
            subprocess.run(['/usr/bin/hdiutil', 'detach', '-quiet', str(mount)], check=True)
        payload = expanded / 'Payload/usr/local'
        thin = work / 'smartctl'
        subprocess.run(['/usr/bin/lipo', str(payload / 'sbin/smartctl'), '-thin', architecture, '-output', str(thin)], check=True)
        validate_binary(thin, architecture)
        if (payload / 'share/doc/smartmontools/COPYING').read_bytes() != (VENDOR / 'COPYING').read_bytes():
            raise ValueError('Licence smartmontools inattendue.')
        target = app / 'Contents/Helpers/smartctl'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(thin, target)
        target.chmod(0o755)
        notices = app / 'Contents/Resources/smartmontools'
        shutil.copytree(VENDOR, notices, dirs_exist_ok=True)
        shutil.copyfile(payload / 'share/smartmontools/drivedb.h', notices / 'drivedb.h')
        # Supply the exact unmodified source alongside the GPL executable, not only a URL.
        shutil.copyfile(source, notices / 'smartmontools-source.tar.gz')
    print('==> smartctl 7.5 embarqué avec sa base et ses sources, sans installation système')


if __name__ == '__main__':
    embed(Path(sys.argv[1]))
