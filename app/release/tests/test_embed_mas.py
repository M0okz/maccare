import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from app.release import embed_mas


class EmbeddedMasTests(unittest.TestCase):
    def test_modified_archive_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'mas.pkg'
            archive.write_bytes(b'official archive fixture')
            expected = hashlib.sha256(archive.read_bytes()).hexdigest()
            embed_mas.verify_archive(archive, expected)
            archive.write_bytes(b'changed archive')
            with self.assertRaises(ValueError):
                embed_mas.verify_archive(archive, expected)

    def test_unknown_architecture_fails_before_any_download(self):
        with patch('urllib.request.urlopen') as download:
            with self.assertRaises(ValueError):
                embed_mas.embed(Path('/unused/MacCare.app'), 'unsupported')
            download.assert_not_called()

    def test_external_libraries_or_newer_macos_are_rejected(self):
        cases = [
            ['arm64', ' minos 13.0\n', 'mas:\n\t/opt/homebrew/lib/libtest.dylib (version)'],
            ['arm64', ' minos 14.0\n', 'mas:\n\t/usr/lib/libSystem.B.dylib (version)'],
            ['x86_64', ' minos 13.0\n', 'mas:\n\t/usr/lib/libSystem.B.dylib (version)'],
        ]
        for output in cases:
            with self.subTest(output=output), patch('subprocess.check_output', side_effect=output):
                with self.assertRaises(ValueError):
                    embed_mas.validate_binary(Path('/fixture/mas'), 'arm64')

    def test_system_only_binary_at_supported_minimum_is_accepted(self):
        with patch('subprocess.check_output', side_effect=[
            'arm64', ' minos 13.0\n', 'mas:\n\t/usr/lib/libSystem.B.dylib (version)\n\t/System/Library/Frameworks/Foundation.framework/Foundation (version)',
        ]):
            embed_mas.validate_binary(Path('/fixture/mas'), 'arm64')


if __name__ == '__main__':
    unittest.main()
