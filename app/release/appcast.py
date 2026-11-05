#!/usr/bin/env python3
"""Produit et signe un flux Sparkle depuis le DMG final, après notarisation."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
from urllib.parse import quote
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def make_feed(info, repository, archive, signature, notes, published):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Dépôt GitHub invalide.')
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version) or not info['CFBundleVersion'].isdigit():
        raise ValueError('Version invalide.')
    base = f'https://github.com/{repository}/releases/download/v{version}'
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'MacCare'
    ET.SubElement(channel, 'link').text = f'https://github.com/{repository}/releases'
    ET.SubElement(channel, 'description').text = 'Mises à jour de MacCare pour Apple Silicon'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'MacCare {version}'
    ET.SubElement(item, 'pubDate').text = format_datetime(published)
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = info['CFBundleVersion']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = version
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = '13.0.0'
    ET.SubElement(item, f'{{{SPARKLE}}}hardwareRequirements').text = 'arm64'
    ET.SubElement(item, 'description', {f'{{{SPARKLE}}}format': 'markdown'}).text = notes
    ET.SubElement(item, 'enclosure', {
        'url': f'{base}/{quote(archive.name)}', 'length': str(archive.stat().st_size),
        'type': 'application/octet-stream', f'{{{SPARKLE}}}edSignature': signature,
    })
    return ET.ElementTree(rss)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--dmg', type=Path, required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sign-tool', type=Path, required=True)
    args = parser.parse_args()
    key = os.environ.get('MACCARE_SPARKLE_PRIVATE_KEY')
    if not key:
        parser.error('MACCARE_SPARKLE_PRIVATE_KEY est nécessaire pour signer le flux.')
    info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    signature = subprocess.check_output([str(args.sign_tool), '--ed-key-file', '-', '-p', str(args.dmg)],
                                        input=key, text=True).strip()
    if not re.fullmatch(r'[A-Za-z0-9+/]{86}==', signature):
        raise RuntimeError('Le signataire n’a pas produit une signature Ed25519 valide.')
    feed = make_feed(info, args.repository, args.dmg, signature, args.notes.read_text(), datetime.now(timezone.utc))
    ET.indent(feed, space='  ')
    feed.write(args.output, encoding='utf-8', xml_declaration=True)
    subprocess.run([str(args.sign_tool), '--ed-key-file', '-', str(args.output)], input=key, text=True, check=True)
    subprocess.run([str(args.sign_tool), '--ed-key-file', '-', '--verify', str(args.output)], input=key, text=True, check=True)
    subprocess.run([str(args.sign_tool), '--ed-key-file', '-', '--verify', str(args.dmg), signature],
                   input=key, text=True, check=True)


if __name__ == '__main__':
    main()
