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
  self.assertEqual(len(frozen['npcs']),15)
  ids=[]
  for script,warp in [('wpm_300_247_222','30301,23,37'),('wpm_300_182_162','30307,10,6')]:
   gate=next(n for n in module['npcs'] if n['source_script']=='genout/'+script)
   self.assertEqual(gate['events'],[4,46])
   self.assertEqual(gate['branches'][0]['condition'],'LV>64&ENDEV=4')
   self.assertEqual(gate['branches'][0]['actions'],{'Warp':warp});ids.append(gate['id'])
  self.assertEqual(oracle['always_active_npc_ids'],ids)
  text=(ROOT/'references/chenmingbiao-stone-age/gmsv/data/npc/genout/npcgen.template').read_text(encoding='gb18030')
  import re
  blocks=[block for block in re.findall(r'\{([^}]+)\}',text) if 'templatename=npcgen_warpman\n' in block]
  self.assertEqual(len(blocks),1);self.assertIn('functionset=WarpMan',blocks[0])
  self.assertEqual(set(map(int,frozen['manifest']['world']['map_sources'])),set(range(21201,21216))|set(range(21301,21316))|set(range(30301,30308))|{31301,31302})
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
