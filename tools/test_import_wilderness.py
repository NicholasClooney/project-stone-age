"""Deterministic map-import contracts; no original assets required or written."""
import contextlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import import_wilderness


class FakeArchive:
    def __init__(self, _source):
        self.map_ids = {100: 10, 101: 11, 102: 12}
        self.entries = {
            10: dict(x=0, y=0, w=2, h=2, ex=1, ey=1, hit=2, priority=0),
            11: dict(x=0, y=0, w=2, h=2, ex=2, ey=2, hit=0, priority=0),
            12: dict(x=0, y=0, w=2, h=2, ex=2, ey=2, hit=2, priority=0),
        }

    def image(self, _ident):
        return Image.new('RGB', (2, 2), (10, 20, 30))


class WildernessImportTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name)
        self.source = self.output / 'map.dat'
        (self.output / 'samgir.json').write_text(json.dumps(dict(images={}, characters={'hero': {}})))
        # Full dimensions are deliberate: exercise exact big-endian offsets and
        # map bounds rather than mock away the original format contract.
        self.raw = bytearray(44 + 800 * 800 * 4)
        self.raw[:6] = b'LS2MAP'
        struct.pack_into('>HH', self.raw, 40, 800, 800)
        self.raw[44:44 + 800 * 800 * 2] = struct.pack('>H', 100) * (800 * 800)

    def cell(self, x, y, value, prop=False):
        offset = 44 + ((y + 448) * 800 + x + 592) * 2
        if prop:
            offset += 800 * 800 * 2
        struct.pack_into('>H', self.raw, offset, value)

    def run_import(self):
        self.source.write_bytes(self.raw)
        with patch.object(import_wilderness, 'Archive', FakeArchive), contextlib.redirect_stdout(io.StringIO()):
            import_wilderness.run('unused', self.source, self.output)
        return json.loads((self.output / 'wilderness.json').read_text())

    def test_crop_mapping_and_portal(self):
        self.cell(20, 20, 101, prop=True)
        data = self.run_import()
        self.assertEqual(data['origin'], [592, 448])
        self.assertEqual((data['width'], data['height']), (96, 96))
        self.assertEqual(len(data['ground']), 96 * 96)
        self.assertEqual(data['ground'][0], [0, 0, 10])
        self.assertEqual(data['ground'][-1], [95, 95, 10])
        self.assertEqual(data['objects'], [[20, 20, 11]])
        for x, y in [(20, 20), (21, 20), (20, 19), (21, 19)]:
            self.assertEqual(data['blocked'][y * 96 + x], 1)
        self.assertEqual(data['blocked'][21 * 96 + 20], 0)
        self.assertEqual(data['blocked'][45 * 96 + 45], 0)
        self.assertEqual(data['map_colors']['10'], [10, 20, 30])
        self.assertEqual(data['characters'], {'hero': {}})
        for y in range(96):
            for x in range(96):
                if x < 2 or y < 2 or x >= 94 or y >= 94:
                    self.assertEqual(data['blocked'][y * 96 + x], 1)

    def test_missing_graphics_cannot_be_reopened_by_walkable_objects(self):
        self.cell(20, 20, 999)
        self.cell(20, 20, 102, prop=True)
        self.cell(21, 19, 998, prop=True)
        data = self.run_import()
        self.assertEqual(data['blocked'][20 * 96 + 20], 1)
        self.assertEqual(data['blocked'][19 * 96 + 21], 1)
        report = json.loads((self.output / 'wilderness-provenance.json').read_text())
        self.assertIn([612, 468, 999], report['missing_graphics'])
        self.assertIn([613, 467, 998], report['missing_graphics'])

    def test_blocked_portal_rejected(self):
        self.cell(45, 45, 101, prop=True)
        with self.assertRaisesRegex(ValueError, 'destination is blocked'):
            self.run_import()
        self.assertFalse((self.output / 'wilderness.json').exists())

    def test_malformed_headers_and_lengths_rejected(self):
        valid = self.raw
        for bad in [b'', b'LS2MAP', b'INVALID' + valid[7:], valid[:-1], valid + b'x']:
            with self.subTest(size=len(bad)):
                self.raw = bad
                with self.assertRaises(ValueError):
                    self.run_import()
        self.raw = valid
        struct.pack_into('>HH', self.raw, 40, 799, 800)
        with self.assertRaises(ValueError):
            self.run_import()


if __name__ == '__main__':
    unittest.main()
