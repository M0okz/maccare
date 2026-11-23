import copy
import hashlib
from pathlib import Path
import plistlib
import unittest

from app.release.configure_helper import configure, validate_battery_build


class HelperConfigurationTests(unittest.TestCase):
    def test_public_trial_requires_explicit_delivery_choice(self):
        environment = {'MACCARE_M1_MAX_BATTERY_TRIAL':'1', 'MACCARE_DISTRIBUTION':'1'}
        with self.assertRaisesRegex(ValueError, 'MACCARE_PUBLIC_M1_MAX_TRIAL'):
            validate_battery_build({'m1MaxTrialBuild':True}, environment)
        validate_battery_build({'m1MaxTrialBuild':True}, dict(environment, MACCARE_PUBLIC_M1_MAX_TRIAL='1'))
        validate_battery_build({'m1MaxTrialBuild':True}, {'MACCARE_M1_MAX_BATTERY_TRIAL':'1'})
        validate_battery_build({'m1MaxTrialBuild':False}, {'MACCARE_DISTRIBUTION':'1'})

    def test_public_choice_does_not_hide_a_mismatched_or_unknown_binary(self):
        environment = {'MACCARE_M1_MAX_BATTERY_TRIAL':'1', 'MACCARE_DISTRIBUTION':'1', 'MACCARE_PUBLIC_M1_MAX_TRIAL':'1'}
        for info in [{}, {'m1MaxTrialBuild':'true'}, {'m1MaxTrialBuild':False}]:
            with self.subTest(info=info), self.assertRaises(ValueError):
                validate_battery_build(info, environment)
        with self.assertRaises(ValueError):
            validate_battery_build({'m1MaxTrialBuild':True}, {})

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
