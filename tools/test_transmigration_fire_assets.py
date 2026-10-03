"""Imported fire content retains original pixels and required map/pack coverage."""
import json
from pathlib import Path
import unittest
from PIL import Image
from import_legacy import Archive
from map_file import load_map
import plan_web_packs
ROOT=Path(__file__).resolve().parents[1];LEGACY=ROOT/'client/assets/legacy'
class FireAssets(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.spec=json.loads((ROOT/'tools/transmigration_fire_quest_sources.json').read_text())
  cls.catalog=json.loads((LEGACY/'quests/catalog.json').read_text())
  cls.world=json.loads((LEGACY/'world/manifest.json').read_text())
  cls.plan=plan_web_packs.plan();cls.source=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')
 def test_all_item_and_npc_pixels(self):
  for ident in self.spec['items']:
   item=self.catalog['items'][str(ident)];path=item['icon_path']
   with self.subTest(item=ident):
    self.assertIn(plan_web_packs.RES+path,self.plan['packs']['core'])
    with Image.open(LEGACY/path) as im:self.assertEqual(im.convert('RGBA').tobytes(),self.source.image(int(item['bitmap_id'])).convert('RGBA').tobytes())
  for npc in self.catalog['npcs']:
   if npc.get('source_script') not in {**self.spec['scripts'],**self.spec['handlers']}:continue
   with self.subTest(npc=npc['id']):
    with Image.open(LEGACY/npc['path']) as im:self.assertEqual(im.convert('RGBA').tobytes(),self.source.image(int(npc['bitmap_id'])).convert('RGBA').tobytes())
 def test_maps_and_original_gate_replacement(self):
  for mid in self.spec['world']['map_sources']:
   self.assertFalse(self.world['maps'][mid].get('dev_only',False))
   header=load_map(LEGACY/self.world['maps'][mid]['path'],header_only=True)
   files={p for pack in self.plan['maps'][mid] for p in self.plan['packs'][pack]}
   self.assertIn(plan_web_packs.RES+self.world['maps'][mid]['path'],files)
   for key in header['images']:self.assertIn(plan_web_packs.RES+f'images/{key}.png',files)
  self.assertFalse(any(p.get('gate_source') in self.spec['world']['restored_scripts'] for p in self.world['portals']))
  self.assertTrue(self.world['maps']['32021']['dev_only'])
  self.assertEqual(self.world['provenance']['fallback_graphics']['logical_ids'],[15401])
if __name__=='__main__':unittest.main()
