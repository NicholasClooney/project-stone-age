import unittest
import tempfile
import json
import hashlib
from pathlib import Path

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


class PaletteTest(unittest.TestCase):
    def test_exact_indices_reject_new_colors_and_alpha(self):
        palette = [(255,0,255),(3,4,5)] + [(3,4,5)]*254
        image = Image.new('RGBA',(3,1))
        image.putdata([(3,4,5,255),(9,8,7,0),(3,4,5,255)])
        result = build_pet_thumbs.indexed(image,palette)
        self.assertEqual(list(result.getdata()),[1,0,1])
        for bad in [(3,4,5,128),(7,8,9,255)]:
            with self.assertRaises(ValueError):
                build_pet_thumbs.indexed(Image.new('RGBA',(1,1),bad),palette)

    def test_build_preserves_old_bytes_layout_and_nearest_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            assets = Path(tmp)
            battle = assets/'battle'
            (battle/'sheets').mkdir(parents=True)
            image = Image.new('P',(257,131))
            colors = [(255,0,255),(3,4,5),(9,11,13)] + [(3,4,5)]*253
            image.putpalette([v for c in colors for v in c])
            image.putdata([1 if i%3 else 2 for i in range(257*131)])
            image.save(battle/'sheets/a.png',transparency=0)
            manifest = {'characters':{'1':{'3_1':{'frames':[{'image':7}]}}},'sheets':{'1':{'files':['sheets/a.png'],'frames':{'7':[0,0,0,257,131]}}}}
            (battle/'manifest.json').write_text(json.dumps(manifest))
            first = build_pet_thumbs.build(assets)
            hashes = {n:hashlib.sha256((assets/'thumbs'/n).read_bytes()).hexdigest() for n in first['files']}
            second = build_pet_thumbs.build(assets)
            self.assertEqual(first,second)
            self.assertEqual(hashes,{n:hashlib.sha256((assets/'thumbs'/n).read_bytes()).hexdigest() for n in second['files']})
            number,x,y,w,h = first['sprites']['1']
            with Image.open(assets/'thumbs'/first['palette_files'][number]) as atlas:
                actual = atlas.convert('RGBA').crop((x,y,x+w,y+h))
                expected = image.convert('RGBA').resize((w,h),Image.Resampling.NEAREST)
                self.assertEqual(actual.tobytes(),expected.tobytes())
            with Image.open(assets/'thumbs'/first['files'][number]) as atlas:
                expected = image.convert('RGBA').resize((w,h),Image.Resampling.LANCZOS)
                self.assertEqual(atlas.crop((x,y,x+w,y+h)).tobytes(),expected.tobytes())

    @unittest.skipUnless(Path('client/assets/legacy/thumbs/index.json').exists(),'original assets required')
    def test_all_real_frames_share_battle_palette_and_exact_nearest_pixels(self):
        assets = Path('client/assets/legacy')
        index = json.loads((assets/'thumbs/index.json').read_text())
        self.assertEqual(len(index['files']),len(index['palette_files']))
        palette = build_pet_thumbs.battle_palette(assets/'battle')
        entries = build_pet_thumbs.entries(assets/'battle')
        cache = {}
        atlases = []
        for name in index['palette_files']:
            with Image.open(assets/'thumbs'/name) as atlas:
                self.assertEqual(atlas.mode,'P')
                self.assertEqual(atlas.getpalette(),[v for c in palette for v in c])
                self.assertEqual(atlas.info['transparency'],0)
                atlases.append(atlas.convert('RGBA'))
        for sprite,spot in index['sprites'].items():
            number,x,y,w,h = spot
            atlas = atlases[number]
            self.assertTrue(x>=0 and y>=0 and x+w<=atlas.width and y+h<=atlas.height)
            animations,sheets = entries[sprite]
            expected = build_pet_thumbs.picture(assets/'battle',sheets,build_pet_thumbs.standing_frame(animations),cache,Image.Resampling.NEAREST)
            actual = atlas.crop((x,y,x+w,y+h))
            self.assertEqual(actual.size,expected.size,sprite)
            # Hidden RGB of transparent texels is immaterial; visible RGBA and
            # every alpha byte are exact, including all downscaled originals.
            self.assertEqual(actual.getchannel('A').tobytes(),expected.getchannel('A').tobytes(),sprite)
            self.assertEqual([p if p[3] else (0,0,0,0) for p in actual.getdata()],
                             [p if p[3] else (0,0,0,0) for p in expected.getdata()],sprite)


if __name__ == '__main__':
    unittest.main()
