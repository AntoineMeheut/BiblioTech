import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


content = load('content', 'content.py')
maps = load('maps', 'check-map.py')


class Downloads(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.body = b'ZIM test payload\x00' * 10
        self.entry = {'id': 'example_fr_2026-01', 'url': 'https://download.kiwix.org/zim/other/example_fr_2026-01.zim',
                      'bytes': len(self.body), 'sha256': hashlib.sha256(self.body).hexdigest()}
        self.target = self.root / (self.entry['id'] + '.zim')

    def test_existing_verified_file_is_not_downloaded(self):
        self.target.write_bytes(self.body)
        with patch.object(content.subprocess, 'run') as run:
            self.assertEqual(content.download_one(self.entry, self.root), self.target)
            run.assert_not_called()

    def test_existing_corrupt_file_is_preserved(self):
        self.target.write_bytes(b'x' * len(self.body))
        with self.assertRaisesRegex(ValueError, 'corrompu'):
            content.download_one(self.entry, self.root)
        self.assertEqual(self.target.read_bytes(), b'x' * len(self.body))

    def test_resume_promotes_only_complete_verified_file(self):
        part = self.target.with_suffix('.zim.part')
        part.write_bytes(self.body[:20])

        def transfer(command, **kwargs):
            self.assertIn('--continue-at', command)
            self.assertEqual(command[command.index('--output') + 1], str(part))
            with part.open('ab') as f:
                f.write(self.body[20:])

        with patch.object(content.subprocess, 'run', side_effect=transfer):
            content.download_one(self.entry, self.root)
        self.assertEqual(self.target.read_bytes(), self.body)
        self.assertFalse(part.exists())

    def test_interrupted_download_never_becomes_zim(self):
        part = self.target.with_suffix('.zim.part')

        def transfer(command, **kwargs):
            part.write_bytes(self.body[:20])
            raise subprocess.CalledProcessError(18, command)

        with patch.object(content.subprocess, 'run', side_effect=transfer):
            with self.assertRaises(subprocess.CalledProcessError):
                content.download_one(self.entry, self.root)
        self.assertFalse(self.target.exists())
        self.assertEqual(part.stat().st_size, 20)

    def test_bad_hash_is_not_promoted(self):
        part = self.target.with_suffix('.zim.part')
        part.write_bytes(b'x' * len(self.body))
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            content.download_one(self.entry, self.root)
        self.assertFalse(self.target.exists())

    def test_complete_partial_does_not_issue_invalid_range_request(self):
        self.target.with_suffix('.zim.part').write_bytes(self.body)
        with patch.object(content.subprocess, 'run') as run:
            content.download_one(self.entry, self.root)
            run.assert_not_called()

    def test_disk_reserve_is_checked_before_download(self):
        usage = type('Usage', (), {'free': 1})()
        with patch.object(content.shutil, 'disk_usage', return_value=usage):
            with self.assertRaisesRegex(ValueError, 'Espace insuffisant'):
                content.download_one(self.entry, self.root)

    def test_offline_missing_file_does_not_download(self):
        with patch.object(content.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'manquante'):
                content.download_one(self.entry, self.root, offline=True)
            run.assert_not_called()

    def test_failed_index_keeps_previous_library(self):
        dest = self.root / 'library.xml'
        dest.write_text('old library')
        with patch.object(content.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'kiwix-manage')):
            with self.assertRaises(subprocess.CalledProcessError):
                content.build_index([self.target], dest)
        self.assertEqual(dest.read_text(), 'old library')
        self.assertEqual(list(self.root.glob('library-*.xml')), [])

    def test_empty_successful_index_is_rejected(self):
        with patch.object(content.subprocess, 'run'):
            with self.assertRaisesRegex(ValueError, 'Index incomplet'):
                content.build_index([self.target], self.root / 'library.xml')
        self.assertFalse((self.root / 'library.xml').exists())

    def test_requested_manifest_keeps_all_exact_versions(self):
        entries = content.manifest(ROOT / 'config/contents.json')
        self.assertEqual(len(entries), 15)
        self.assertIn('wikivoyage_fr_all_maxi_2026-07c', [e['id'] for e in entries])
        self.assertEqual(sum(e['bytes'] for e in entries), 105346030965)


class MapValidation(unittest.TestCase):
    def create(self, layers=('water', 'transportation', 'place')):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / 'map.pmtiles'
        meta = json.dumps({'vector_layers': [{'id': x} for x in layers]}).encode()
        header = bytearray(127)
        header[:8] = b'PMTiles\x03'
        struct.pack_into('<QQ', header, 8, 127, 1)
        struct.pack_into('<QQ', header, 24, 128, len(meta))
        struct.pack_into('<QQ', header, 56, 128 + len(meta), 1)
        header[97] = 1
        header[99] = 1
        header[101] = 14
        path.write_bytes(header + b'X' + meta + b'T')
        return path

    def test_compatible_map_header(self):
        self.assertEqual(maps.check(self.create())['maxzoom'], 14)

    def test_truncated_map_is_rejected(self):
        path = self.create()
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, 'tronqué'):
            maps.check(path)

    def test_wrong_schema_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'OpenMapTiles'):
            maps.check(self.create(('roads', 'places')))


if __name__ == '__main__':
    unittest.main()
