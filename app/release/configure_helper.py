"""Record the packaged app's version and channel in its helper descriptor."""
import os
from pathlib import Path
import plistlib
import re
import sys


def validate_battery_build(info, environment):
    """Keep the compiled battery mode and the explicitly chosen delivery aligned."""
    trial = info.get('m1MaxTrialBuild')
    if not isinstance(trial, bool):
        raise ValueError('Le helper ne fournit pas un mode batterie valide.')
    if trial != (environment.get('MACCARE_M1_MAX_BATTERY_TRIAL') == '1'):
        raise ValueError('Le mode M1 Max du helper ne correspond pas au paquet demandé. Recompilez avec le même mode.')
    if trial and environment.get('MACCARE_DISTRIBUTION') == '1' and environment.get('MACCARE_PUBLIC_M1_MAX_TRIAL') != '1':
        raise ValueError('La publication du mode M1 Max en validation exige MACCARE_PUBLIC_M1_MAX_TRIAL=1.')


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
