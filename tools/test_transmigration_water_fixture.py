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
  self.assertEqual(len(frozen['npcs']),13)
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
