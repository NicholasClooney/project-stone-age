import unittest

from PIL import Image

import build_pet_thumbs


class PackTest(unittest.TestCase):
    def test_pack_places_every_picture_without_overlap(self):
        pictures = {str(i): Image.new('RGBA', (100+i % 28, 60+i % 68)) for i in range(150)}
        sheets = build_pet_thumbs.pack(pictures)
        placed = {}
        for number, (atlas, places) in enumerate(sheets):
            self.assertEqual(atlas.size, (build_pet_thumbs.ATLAS, build_pet_thumbs.ATLAS))
            boxes = []
            for sprite, (x, y, w, h) in places.items():
                self.assertEqual((w, h), pictures[sprite].size)
                self.assertTrue(x+w <= build_pet_thumbs.ATLAS and y+h <= build_pet_thumbs.ATLAS)
                for (a, b, c, d) in boxes:
                    self.assertFalse(x < a+c and a < x+w and y < b+d and b < y+h, f'{sprite} overlaps')
                boxes.append((x, y, w, h))
                placed[sprite] = number
        self.assertEqual(set(placed), set(pictures))
        self.assertGreater(len(sheets), 1)

    def test_standing_frame_prefers_facing_one(self):
        frames = {'3_0': {'frames': [{'image': 5}]}, '3_1': {'frames': [{'image': 7}]}}
        self.assertEqual(build_pet_thumbs.standing_frame(frames), 7)
        self.assertEqual(build_pet_thumbs.standing_frame({'3_0': {'frames': [{'image': 5}]}}), 5)
        self.assertIsNone(build_pet_thumbs.standing_frame({}))


if __name__ == '__main__':
    unittest.main()
