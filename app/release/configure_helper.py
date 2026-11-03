"""Record the packaged app's version and channel in its helper descriptor."""
import os
from pathlib import Path
import plistlib
import re
import sys


def configure(helper, info, distribution):
    build = info['CFBundleVersion']
    version = info['CFBundleShortVersionString']
    if not isinstance(build, str) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Le numéro interne de l’assistant doit être positif.')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('La version de l’assistant doit correspondre à celle de l’app.')
    helper = dict(helper)
    environment = dict(helper.get('EnvironmentVariables', {}))
    environment.update(MACCARE_HELPER_VERSION=version, MACCARE_HELPER_BUILD=build,
                       MACCARE_HELPER_CHANNEL='distribution' if distribution else 'development')
    helper['EnvironmentVariables'] = environment
    return helper


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    bundle = Path(sys.argv[1]).resolve()
    if not bundle.is_relative_to(root/'build') or bundle.name != 'MacCare.app':
        raise SystemExit('Le paquet doit être placé sous build/.')
    path = bundle/'Contents/Library/LaunchDaemons/org.maccare.helper.plist'
    info = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    helper = configure(plistlib.loads(path.read_bytes()), info, os.environ.get('MACCARE_DISTRIBUTION') == '1')
    path.write_bytes(plistlib.dumps(helper))
