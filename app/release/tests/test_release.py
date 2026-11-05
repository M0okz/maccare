import base64
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest.mock import patch

from app.release.appcast import make_feed, SPARKLE
from app.release.configure_bundle import configure
from app.release import ci_signing


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.info = {'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1'}
        self.public_key = base64.b64encode(bytes(range(32))).decode()
        self.feed = 'https://github.com/M0okz/maccare/releases/latest/download/appcast.xml'

    def test_distribution_requires_public_configuration_and_positive_build(self):
        for environment in [{'MACCARE_DISTRIBUTION': '1'}, {'MACCARE_BUILD_NUMBER': '0'},
                            {'MACCARE_VERSION': 'v0.1.0'}, {'MACCARE_VERSION': '0.1.0\nignored'},
                            {'MACCARE_UPDATE_FEED_URL': self.feed}]:
            with self.assertRaises(ValueError):
                configure(self.info, environment)

    def test_development_build_has_no_live_updater_configuration(self):
        configured = configure(dict(self.info, SUFeedURL=self.feed, SUPublicEDKey=self.public_key), {})
        self.assertNotIn('SUFeedURL', configured)
        self.assertNotIn('SUPublicEDKey', configured)
        self.assertTrue(configured['MacCareDevelopmentBuild'])
        self.assertEqual(configured['CFBundleDisplayName'], 'MacCare Dev')

    def test_distribution_injects_public_fields_and_keeps_source_unchanged(self):
        configured = configure(dict(self.info, MacCareDevelopmentBuild=True, CFBundleName='MacCare Dev',
                                    CFBundleDisplayName='MacCare Dev'),
                              {'MACCARE_DISTRIBUTION': '1', 'MACCARE_VERSION': '0.2.0',
                              'MACCARE_BUILD_NUMBER': '42', 'MACCARE_UPDATE_FEED_URL': self.feed,
                              'MACCARE_SPARKLE_PUBLIC_KEY': self.public_key})
        self.assertEqual(configured['CFBundleVersion'], '42')
        self.assertEqual(configured['CFBundleShortVersionString'], '0.2.0')
        self.assertEqual(configured['SUPublicEDKey'], self.public_key)
        self.assertFalse(configured['MacCareDevelopmentBuild'])
        self.assertEqual(configured['CFBundleName'], 'MacCare')
        self.assertEqual(configured['CFBundleDisplayName'], 'MacCare')
        self.assertEqual(self.info['CFBundleVersion'], '1')

    def test_configuration_rejects_authentication_in_feed_url(self):
        for url in ['http://github.com/feed', 'https://token@github.com/feed', 'https://github.com/feed?token=x',
                    'file:///tmp/appcast.xml', 'https://github.com/feed#fragment']:
            with self.assertRaises(ValueError):
                configure(self.info, {'MACCARE_UPDATE_FEED_URL': url, 'MACCARE_SPARKLE_PUBLIC_KEY': self.public_key})

    def test_feed_uses_internal_build_exact_archive_size_and_arm64_requirement(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'MacCare-0.1.0-arm64.dmg'
            archive.write_bytes(b'test archive bytes')
            tree = make_feed(dict(self.info, CFBundleVersion='42'), 'M0okz/maccare', archive, 'test-signature',
                             '<notes & details>', datetime(2026, 11, 3, tzinfo=timezone.utc))
            item = tree.getroot().find('channel/item')
            self.assertEqual(item.find(f'{{{SPARKLE}}}version').text, '42')
            self.assertEqual(item.find(f'{{{SPARKLE}}}hardwareRequirements').text, 'arm64')
            self.assertEqual(item.find(f'{{{SPARKLE}}}minimumSystemVersion').text, '13.0.0')
            self.assertEqual(item.find('enclosure').get('length'), str(archive.stat().st_size))
            self.assertEqual(item.find('enclosure').get('url'),
                             'https://github.com/M0okz/maccare/releases/download/v0.1.0/MacCare-0.1.0-arm64.dmg')
            self.assertEqual(item.find('description').text, '<notes & details>')

    def test_signing_preflight_accepts_either_complete_notary_route_without_importing_keys(self):
        common = {name: 'isolated-test' for name in ci_signing.NAMES}
        for names in [('MACCARE_APPLE_ID', 'MACCARE_APPLE_TEAM_ID', 'MACCARE_NOTARY_PASSWORD'),
                      ('MACCARE_NOTARY_KEY_P8', 'MACCARE_NOTARY_KEY_ID', 'MACCARE_NOTARY_ISSUER_ID')]:
            with tempfile.TemporaryDirectory() as directory:
                environment = dict(common, RUNNER_TEMP=directory)
                environment.update({name: 'isolated-test' for name in names})
                with patch.dict('os.environ', environment, clear=True), patch('sys.argv', ['ci_signing.py', 'check']), redirect_stdout(StringIO()):
                    ci_signing.main()
                self.assertFalse((Path(directory) / 'maccare-signing').exists())

    def test_signing_preflight_rejects_missing_notary_fields_without_showing_values(self):
        environment = {name: 'isolated-test' for name in ci_signing.NAMES}
        environment.update(RUNNER_TEMP='/tmp', MACCARE_APPLE_ID='isolated-test')
        with patch.dict('os.environ', environment, clear=True), patch('sys.argv', ['ci_signing.py', 'check']):
            with self.assertRaises(SystemExit) as error:
                ci_signing.main()
        self.assertNotIn('isolated-test', str(error.exception))


if __name__ == '__main__':
    unittest.main()
