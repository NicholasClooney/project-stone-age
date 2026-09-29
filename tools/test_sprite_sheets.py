"""Sheet packing and lossless palette conversion (tools/sprite_sheets.py)."""
import tempfile
import unittest
from pathlib import Path
class SheetTest(unittest.TestCase):
    def frames(self):
        from PIL import Image
        sizes = {1: (30, 40), 2: (50, 20), 3: (10, 10), 4: (64, 64)}
        return {i: Image.new('RGBA', size, (i * 40, 0, 0, 255)) for i, size in sizes.items()}

    def test_every_frame_is_placed_without_overlap_and_copied(self):
        from sprite_sheets import pack_sheets
        frames = self.frames()
        sheets, spots = pack_sheets(frames)
        self.assertEqual(len(sheets), 1)
        boxes = []
        for ident, (sheet, x, y, w, h) in spots.items():
            self.assertEqual((w, h), frames[ident].size)
            self.assertEqual(sheets[sheet].crop((x, y, x + w, y + h)).tobytes(), frames[ident].tobytes())
            for other in boxes:
                self.assertFalse(x < other[2] and other[0] < x + w and y < other[3] and other[1] < y + h, ident)
            boxes.append((x, y, x + w, y + h))

    def test_frames_that_do_not_fit_one_sheet_start_another(self):
        from sprite_sheets import pack_sheets
        sheets, spots = pack_sheets(self.frames(), limit=70)
        self.assertGreater(len(sheets), 1)
        self.assertTrue(all(s.width <= 70 and s.height <= 70 for s in sheets))
        self.assertEqual(set(spots), {1, 2, 3, 4})

    def test_a_frame_larger_than_a_sheet_is_refused(self):
        from sprite_sheets import pack_sheets
        with self.assertRaises(ValueError):
            pack_sheets(self.frames(), limit=60)

    def test_palette_sheets_are_lossless(self):
        from PIL import Image
        from sprite_sheets import pack_sheets, to_palette
        frames = self.frames()
        frames[5] = Image.new('RGBA', (8, 8), (0, 0, 0, 255))
        frames[6] = Image.new('RGBA', (8, 8), (255, 0, 255, 255))
        sheet = pack_sheets(frames)[0][0]
        small = to_palette(sheet)
        self.assertEqual(small.mode, 'P')
        visible = lambda image: [p if p[3] else (0, 0, 0, 0) for p in image.convert('RGBA').getdata()]
        self.assertEqual(visible(small), visible(sheet))

    def test_partial_alpha_stays_rgba(self):
        from PIL import Image
        from sprite_sheets import to_palette
        sheet = Image.new('RGBA', (4, 4), (10, 20, 30, 128))
        self.assertEqual(to_palette(sheet).mode, 'RGBA')

    def test_save_sheets_records_every_frame(self):
        from sprite_sheets import save_sheets
        with tempfile.TemporaryDirectory() as folder:
            entry = save_sheets(self.frames(), Path(folder), '42')
            self.assertEqual(entry['files'], ['42.png'])
            self.assertEqual(set(entry['frames']), {'1', '2', '3', '4'})
            self.assertTrue((Path(folder) / '42.png').exists())


if __name__ == '__main__':
    unittest.main()
