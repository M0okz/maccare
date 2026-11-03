#!/usr/bin/env python3
"""Injecte les seules métadonnées publiques dans le paquet avant sa signature."""
import base64
import os
from pathlib import Path
import plistlib
import re
import sys
from urllib.parse import urlsplit


def configure(info, environment):
    info = dict(info)
    version = environment.get('MACCARE_VERSION', info['CFBundleShortVersionString'])
    build = environment.get('MACCARE_BUILD_NUMBER', info['CFBundleVersion'])
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Version attendue : major.minor.patch, sans préfixe v.')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Le numéro interne doit être un entier strictement positif.')
    info.update(CFBundleShortVersionString=version, CFBundleVersion=build)
    feed = environment.get('MACCARE_UPDATE_FEED_URL', '')
    public_key = environment.get('MACCARE_SPARKLE_PUBLIC_KEY', '')
    if environment.get('MACCARE_DISTRIBUTION') == '1' and not (feed and public_key):
        raise ValueError('Une distribution exige un flux public et une clé publique Sparkle.')
    if bool(feed) != bool(public_key):
        raise ValueError('Le flux et la clé publique Sparkle doivent être fournis ensemble.')
    if feed:
        parsed = urlsplit(feed)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('Le flux Sparkle doit être HTTPS, sans identifiant ni jeton.')
        if len(base64.b64decode(public_key, validate=True)) != 32:
            raise ValueError('Clé publique Ed25519 invalide.')
        info.update(SUFeedURL=feed, SUPublicEDKey=public_key)
    else:
        info.pop('SUFeedURL', None)
        info.pop('SUPublicEDKey', None)
    return info


if __name__ == '__main__':
    path = Path(sys.argv[1])
    info = configure(plistlib.loads(path.read_bytes()), os.environ)
    path.write_bytes(plistlib.dumps(info))
