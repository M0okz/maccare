import json
from pathlib import Path
import tempfile
import unittest

from app.release.intent_metadata import constant_files


class IntentMetadataTests(unittest.TestCase):
    def fixture(self, root, target, configuration='Release', architecture='arm64', module='MacCare'):
        folder = root / f'app/.build/out/Intermediates.noindex/MacCare.build/{configuration}/{target}/Objects-normal/{architecture}'
        folder.mkdir(parents=True)
        constants = folder / f'{module}-primary.swiftconstvalues'
        constants.write_text('{}')
        source = root / f'app/Sources/{module}/BatteryAppIntents.swift'
        (folder / f'{module}-OutputFileMap.json').write_text(json.dumps({
            '': {'const-values': str(constants)}, str(source): {'object': 'unused.o'},
        }))
        return constants

    def test_resolves_both_xcode_target_directory_layouts(self):
        for target in ('MacCare.build', 'MacCare-p.build'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                expected = self.fixture(root, target)
                self.assertEqual(constant_files(root, 'Release', 'arm64'), [expected])

    def test_ignores_other_architecture_configuration_and_helper(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected = self.fixture(root, 'MacCare.build')
            self.fixture(root, 'MacCare.build', architecture='x86_64')
            self.fixture(root, 'MacCare.build', configuration='Debug')
            self.fixture(root, 'MacCareHelper.build', module='MacCareHelper')
            self.assertEqual(constant_files(root, 'Release', 'arm64'), [expected])

    def test_rejects_missing_constants(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'MacCare.build').unlink()
            with self.assertRaisesRegex(ValueError, 'constants missing'):
                constant_files(root, 'Release', 'arm64')

    def test_rejects_ambiguous_stale_module_products(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, 'MacCare.build')
            self.fixture(root, 'MacCare-p.build')
            with self.assertRaisesRegex(ValueError, 'found 2'):
                constant_files(root, 'Release', 'arm64')
