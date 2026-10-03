"""The previously scenic Phoenix gate retains its exact original OR conditions."""
import hashlib,json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
from quest_source_handlers import keyword_warp
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'references/chenmingbiao-stone-age'
SCRIPT='genout/wpm_20301_200_39'
def fixture():
 paths=['gmsv/data/itemset.txt','gmsv/data/jobdaily.txt','gmsv/data/npc/genout/dungeon01.create','gmsv/data/npc/genout/npcgen.template','gmsv/data/npc/'+SCRIPT]
 # All hashes are pinned in the committed fixture, not accepted dynamically by tests.
 return {'version':1,'id':'fire-gate-fixture','reference_revision':'0c58fb6683a49a178a8ad845a8c296c2cb83bd81','sources':{p:hashlib.sha256((REF/p).read_bytes()).hexdigest() for p in paths},'creates':[paths[2]],'scripts':{},'handlers':{SCRIPT:{'kind':'warpman','events':[40]}},'items':[],'jobs':[],'reward_enemies':[]}
class GateTests(unittest.TestCase):
 def test_source_binding(self):
  expected=json.loads((ROOT/'client/tests/fixtures/transmigration-fire-gate.json').read_text())
  self.assertEqual(load_quest_module(REF,expected['manifest']),expected['module'])
  n=expected['module']['npcs'][0]
  self.assertEqual((n['map_id'],n['cell']),(20301,[200,39]))
  self.assertEqual(n['branches'][0]['condition'],'LV>0&ENDEV=4&ENDEV=40,LV>0&ENDEV=4&NOWEV=40')
 def test_mutations_fail(self):
  source=(REF/('gmsv/data/npc/'+SCRIPT)).read_text(encoding='gb18030')
  for wrong in [source.replace('&ENDEV=4',''),source.replace('20301,200,41','20309,46,45'),source.replace('MONEY:-1','MONEY:0')]:
   with self.assertRaises(ValueError):keyword_warp(wrong,SCRIPT,[40])
if __name__=='__main__':unittest.main()
