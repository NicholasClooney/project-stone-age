"""Actual source pixels and playable water graph, not a headless visual claim."""
import json,unittest
from pathlib import Path
from PIL import Image
from import_legacy import Archive
import plan_web_packs
ROOT=Path(__file__).resolve().parents[1]
LEGACY=ROOT/'client/assets/legacy'
class WaterAssets(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.spec=json.loads((ROOT/'tools/transmigration_water_quest_sources.json').read_text())
  cls.catalog=json.loads((LEGACY/'quests/catalog.json').read_text())
  cls.world=json.loads((LEGACY/'world/manifest.json').read_text())
  cls.plan=plan_web_packs.plan();cls.archive=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')
 def test_all55_actual_item_icons_and_core_pack(self):
  self.assertEqual(len(self.spec['items']),55)
  for i in self.spec['items']:
   with self.subTest(item=i):
    item=self.catalog['items'][str(i)];path=item['icon_path']
    self.assertIn(plan_web_packs.RES+path,self.plan['packs']['core'])
    with Image.open(LEGACY/path) as png:
     self.assertEqual(png.convert('RGBA').tobytes(),self.archive.image(int(item['bitmap_id'])).convert('RGBA').tobytes())
 def test_exact_water_maps_promoted_and_no_king(self):
  for ident in self.spec['world']['map_sources']:
   self.assertFalse(self.world['maps'][ident].get('dev_only',False))
   self.assertIn(ident,self.plan['maps'])
  self.assertTrue(self.world['maps']['32021']['dev_only'])
  self.assertFalse(any(n.get('source_script')=='777/ten.arg' for n in self.catalog['npcs']))
 def test_helper_hunts_use_real_area_group_enemy_edges(self):
  encounters=json.loads((LEGACY/'encounters/catalog.json').read_text())
  for area_id,map_id,group_id,enemy_id in [(570,30305,718,1324),(581,21209,723,1335)]:
   area=next(a for a in encounters['areas'] if a['id']==area_id)
   self.assertEqual(area['map_id'],map_id)
   self.assertIn(group_id,[g['id'] for g in area['groups']])
   self.assertIn(enemy_id,[e['id'] for e in encounters['groups'][str(group_id)]['enemies']])
 def test_both_original_lake_entries_preserved(self):
  # Exact source-backed ordinary graph: Ford access must never acquire the
  # separate village40 fee/pass/quest requirements.
  expected=[(5000,[46,18],31301,[10,10],61),
            (31301,[10,10],5000,[46,18],70),
            (31301,[9,51],31302,[52,11],88),
            (31302,[52,11],31301,[9,51],97)]
  for origin,cell,destination,target,line in expected:
   actual=[p for p in self.world['portals'] if p['from_map']==origin and p['cell']==cell]
   self.assertEqual(actual,[dict(from_map=origin,cell=cell,to_map=destination,target=target,source=f'dungeon03.create:{line}')])
  scripts={n.get('source_script'):n for n in self.catalog['npcs']}
  paid=scripts['genout/wpm_40_13_1']['branches'][0]
  self.assertEqual(paid['condition'],'LV>0')
  self.assertEqual(paid['actions'],{'Warp':'31301,10,104','DelStone':'300'})
  back=scripts['genout/wpm_200_316_711']['branches'][0]
  self.assertEqual(back['condition'],'LV>64&ENDEV=46&ITEM=2766')
  self.assertEqual(back['actions'],{'Warp':'21301,7,3'})
 def test_original_doors_not_convenience(self):
  portals=self.world['portals']
  for script in self.spec['handlers']:
   self.assertFalse(any(p.get('gate_source')==script for p in portals))
  matches=[p for p in portals if p['from_map']==21215 and p['cell']==[26,11]]
  self.assertEqual(len(matches),1);self.assertEqual(matches[0]['to_map'],21315);self.assertEqual(matches[0]['target'],[52,59])
if __name__=='__main__':unittest.main()
