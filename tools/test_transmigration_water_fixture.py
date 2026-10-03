"""Frozen source fixture used by arrival integration without enabling water46."""
import json, unittest
from pathlib import Path
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
class WaterFixture(unittest.TestCase):
 def test_pinned_original_module_matches_complete_fixture(self):
  frozen=json.loads((ROOT/'client/tests/fixtures/transmigration-water-source.json').read_text())
  oracle=json.loads((ROOT/'client/tests/fixtures/transmigration-water.json').read_text())
  module=load_quest_module(ROOT/'references/chenmingbiao-stone-age',frozen['manifest'])
  self.assertEqual(len(frozen['npcs']),14)
  gate=next(n for n in module['npcs'] if n['source_script']=='genout/wpm_300_247_222')
  self.assertEqual(gate['events'],[4,46])
  self.assertEqual(gate['branches'][0]['condition'],'LV>64&ENDEV=4')
  self.assertEqual(gate['branches'][0]['actions'],{'Warp':'30301,23,37'})
  self.assertEqual(oracle['always_active_npc_ids'],[gate['id']])
  self.assertEqual(len(frozen['items']),55)
  self.assertEqual(len(frozen['drops']),13)
  for key in ['npcs','items','drops']:self.assertEqual(frozen[key],module[key])
  self.assertEqual(sorted(frozen['items'],key=int),list(map(str,sorted(oracle['item_ids']))))
  self.assertEqual([n['id'] for n in frozen['npcs']],[n['id'] for n in oracle['npcs']])
  for actual,expected in zip(frozen['npcs'],oracle['npcs']):
   for key,value in expected.items():
    if key=='branches':
     self.assertEqual(len(actual[key]),len(value))
     for branch,wanted in zip(actual[key],value):
      for field,data in wanted.items():self.assertEqual(branch[field],data)
    else:self.assertEqual(actual[key],value)
if __name__=='__main__':unittest.main()
