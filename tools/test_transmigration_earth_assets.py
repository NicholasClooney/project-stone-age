"""Actual earth39 image/pack coverage after the documented import chain."""
import json
from pathlib import Path
import unittest
from PIL import Image
from import_legacy import Archive
from map_file import load_map
import plan_web_packs
ROOT=Path(__file__).resolve().parents[1]
class EarthAssets(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.legacy=ROOT/'client/assets/legacy'
  cls.catalog=json.loads((cls.legacy/'quests/catalog.json').read_text())
  cls.spec=json.loads((ROOT/'tools/transmigration_earth_quest_sources.json').read_text())
  cls.world=json.loads((cls.legacy/'world/manifest.json').read_text())
  cls.plan=plan_web_packs.plan()
  cls.source=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')
 def test_every_reward_icon_original_pixels(self):
  for ident in self.spec['items']:
   with self.subTest(item=ident):
    item=self.catalog['items'][str(ident)];path=item['icon_path']
    self.assertIn(plan_web_packs.RES+path,self.plan['packs']['core'])
    with Image.open(self.legacy/path) as image:
     original=self.source.image(int(item['bitmap_id'])).convert('RGBA')
     self.assertEqual(image.size,original.size)
     self.assertEqual(image.convert('RGBA').tobytes(),original.tobytes())
 def test_earth_maps_palette_and_packs(self):
  checked=set()
  for mid in map(str,range(21001,21016)):
   meta=self.world['maps'][mid];self.assertFalse(meta.get('dev_only',False))
   data=load_map(self.legacy/meta['path'],header_only=True)
   files={p for pack in self.plan['maps'][mid] for p in self.plan['packs'][pack]}
   self.assertIn(plan_web_packs.RES+meta['path'],files)
   for bitmap in data['images']:
    path=f'images/{bitmap}.png';self.assertIn(plan_web_packs.RES+path,files)
    if bitmap in checked:continue
    checked.add(bitmap)
    with Image.open(self.legacy/path) as image:
     self.assertEqual(image.mode,'P');self.assertEqual(image.info.get('transparency'),0)
     self.assertEqual(image.convert('RGBA').convert('RGBa').tobytes(),self.source.image(int(bitmap)).convert('RGBA').convert('RGBa').tobytes())
  self.assertTrue(self.world['maps']['32021']['dev_only'])
if __name__=='__main__':unittest.main()
