"""A selected refresh preserves every unrelated sheet and import sidecar."""
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image
from pack_frame_sheets import pack


class SelectedSheetTests(unittest.TestCase):
    def test_selected_pack_preserves_other_sprites_and_extra_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            images, sheets = root / 'images', root / 'sheets'
            images.mkdir()
            sheets.mkdir()
            new = Image.new('RGBA', (4, 4), 'red')
            new.save(images / '1.png')
            unrelated = sheets / '999.png'
            unrelated.write_bytes(b'unchanged PNG bytes')
            sidecar = sheets / '999.png.import'
            sidecar.write_bytes(b'unchanged import')
            extra = root / 'pet.json'
            extra.write_text(json.dumps({'characters': {'999': {'3_1': {'duration_ms': 800,
                              'frames': [{'image': 2}]}}}, 'images': {'2': {'x': 0, 'y': 0, 'w': 1, 'h': 1}},
                              'sheets': {'999': {'files': ['sheets/999.png'], 'frames': {'2': [0, 0, 0, 1, 1]}}}}))
            extra_bytes = extra.read_bytes()
            manifest = root / 'manifest.json'
            manifest.write_text(json.dumps({'characters': {'101152': {'3_1': {'duration_ms': 800,
                                          'frames': [{'image': 1}]}}},
                                          'images': {'1': {'x': 0, 'y': 0, 'w': 4, 'h': 4}},
                                          'extra_sprites': {'999': 'pet.json'}}))
            pack(manifest, images, sprites=[101152])
            pack(manifest, images, sprites=[101152])  # The second run reads its sheet, not a source PNG.
            self.assertEqual(unrelated.read_bytes(), b'unchanged PNG bytes')
            self.assertEqual(sidecar.read_bytes(), b'unchanged import')
            self.assertEqual(extra.read_bytes(), extra_bytes)
            result = json.loads(manifest.read_text())['sheets']['101152']
            i, x, y, w, h = result['frames']['1']
            with Image.open(root / result['files'][i]) as image:
                self.assertEqual(image.convert('RGBA').crop((x, y, x+w, y+h)).tobytes(), new.tobytes())
            self.assertFalse((images / '1.png').exists())

    def test_unknown_selection_fails_before_altering_existing_sheets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / 'manifest.json'
            manifest.write_text('{"characters":{}}')
            with self.assertRaisesRegex(ValueError, 'Unknown sprites: 101152'):
                pack(manifest, root / 'images', sprites=[101152])
            self.assertEqual(manifest.read_text(), '{"characters":{}}')


if __name__ == '__main__':
    unittest.main()
