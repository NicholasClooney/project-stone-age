"""Directed validation of imported foundation art, palette and web ownership."""
import json
from pathlib import Path
import unittest
from PIL import Image
from import_legacy import Archive
from map_file import load_map
import plan_web_packs

ROOT=Path(__file__).resolve().parents[1]
LEGACY=ROOT/'client/assets/legacy'

class FoundationAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.world=json.loads((LEGACY/'world/manifest.json').read_text())
        cls.catalog=json.loads((LEGACY/'quests/catalog.json').read_text())
        cls.plan=plan_web_packs.plan()
        cls.source=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')

    def test_32021_palette_pixels_and_pack_dependencies(self):
        meta=self.world['maps']['32021']
        self.assertTrue(meta['dev_only'])
        data=load_map(LEGACY/meta['path'],header_only=True)
        packs=self.plan['maps']['32021']
        files={p for pack in packs for p in self.plan['packs'][pack]}
        self.assertIn(plan_web_packs.RES+meta['path'],files)
        palettes=set()
        for key in data['images']:
            with self.subTest(bitmap=key):
                path=f'images/{key}.png'
                self.assertIn(plan_web_packs.RES+path,files)
                with Image.open(LEGACY/path) as image:
                    self.assertEqual(image.mode,'P')
                    self.assertEqual(image.info.get('transparency'),0)
                    palettes.add(tuple(image.getpalette()))
                    self.assertEqual(image.convert('RGBA').convert('RGBa').tobytes(),self.source.image(int(key)).convert('RGBA').convert('RGBa').tobytes())
        self.assertEqual(len(palettes),1)

    def test_29_original_item_icons_are_lossless_in_core(self):
        items=[2698,2699,2700,2701,*range(2706,2719),2735,2736,2758,*range(2766,2775)]
        self.assertEqual(len(items),29)
        for ident in items:
            with self.subTest(item=ident):
                item=self.catalog['items'][str(ident)]
                path=item['icon_path']
                self.assertIn(plan_web_packs.RES+path,self.plan['packs']['core'])
                with Image.open(LEGACY/path) as image:
                    self.assertEqual(image.mode,'RGBA') # palette_images only handles map images/.
                    original=self.source.image(int(item['bitmap_id'])).convert('RGBA')
                    self.assertEqual(image.size,original.size)
                    self.assertEqual(image.convert('RGBA').tobytes(),original.tobytes())

    def test_existing_80_fallback_and_exact_catalog_survive(self):
        fallback=self.world['provenance']['fallback_graphics']
        self.assertEqual(fallback['source'],'.tools/legacy/extracted/SA8.0-20260803')
        self.assertEqual(fallback['logical_ids'],[15401])
        self.assertEqual(fallback['bitmap_namespace'],1000000000)
        self.assertEqual(len(self.catalog['npcs']),242)
        self.assertEqual(len(self.catalog['items']),138)

if __name__=='__main__':unittest.main()
