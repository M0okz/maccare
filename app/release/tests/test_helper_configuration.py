import copy
import hashlib
from pathlib import Path
import plistlib
import unittest

from app.release.configure_helper import configure


class HelperConfigurationTests(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).resolve().parents[2]/'Helper/org.maccare.helper.plist'
        self.helper = plistlib.loads(source.read_bytes())
        self.info = {'CFBundleShortVersionString':'0.2.1','CFBundleVersion':'3'}

    def test_changes_configuration_for_a_new_package_or_signing_channel(self):
        distribution = configure(self.helper, self.info, True)
        development = configure(self.helper, self.info, False)
        updated = configure(self.helper, dict(self.info, CFBundleVersion='4'), True)
        fingerprints = {hashlib.sha256(plistlib.dumps(value)).hexdigest() for value in (distribution, development, updated)}
        self.assertEqual(len(fingerprints), 3)

    def test_preserves_service_identity_recovery_and_launch_policy(self):
        configured = configure(self.helper, self.info, True)
        self.assertEqual({key:value for key,value in configured.items() if key != 'EnvironmentVariables'},
                         {key:value for key,value in self.helper.items() if key != 'EnvironmentVariables'})
        for key,value in self.helper['EnvironmentVariables'].items():
            self.assertEqual(configured['EnvironmentVariables'][key], value)
        self.assertEqual(configured['EnvironmentVariables']['MACCARE_HELPER_BUILD'], '3')
        self.assertEqual(configured['EnvironmentVariables']['MACCARE_HELPER_VERSION'], '0.2.1')
        self.assertEqual(configured['EnvironmentVariables']['MACCARE_HELPER_CHANNEL'], 'distribution')

    def test_does_not_mutate_the_source_descriptor(self):
        original = copy.deepcopy(self.helper)
        configure(self.helper, self.info, True)
        self.assertEqual(self.helper, original)

    def test_rejects_invalid_package_versions(self):
        for info in (dict(self.info, CFBundleVersion='0'), dict(self.info, CFBundleVersion=3),
                     dict(self.info, CFBundleShortVersionString='0.2.1\nignored')):
            with self.subTest(info=info), self.assertRaises(ValueError):
                configure(self.helper, info, True)
