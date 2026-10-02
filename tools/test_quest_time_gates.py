import copy
import unittest
from pathlib import Path
from quest_time_gates import SOURCES, reviewed_time_gates, apply_time_gates
from import_world import read_portals
ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/'references/chenmingbiao-stone-age'
class TimeGateTests(unittest.TestCase):
 def setUp(self):
  self.texts={p:(REFERENCE/p).read_text(encoding='gb18030') for p in SOURCES}
  self.spec={'world':{'time_gates':'dream-cave'}}
 def test_actual_mapwarppoint_and_create_agree(self):
  reviewed=reviewed_time_gates(self.spec,self.texts)
  self.assertEqual([g['time_source_line'] for g in reviewed],[2746,2748,2749,2751,2801])
  portals=read_portals(REFERENCE/'gmsv/data/npc/genout')
  result=apply_time_gates(portals,[{'time_gates':reviewed}])
  self.assertEqual(len([p for p in result if 'requires_time' in p]),5)
  self.assertTrue(any(p.get('source_time_suffix') and 'requires_time' not in p for p in result))
  self.assertTrue(all('requires_time' not in p for p in result if not p.get('source_time_suffix')))
  fixture=__import__('json').loads((ROOT/'client/tests/fixtures/dream-time-gates.json').read_text())
  self.assertEqual(fixture,reviewed)
 def test_module_load_derives_reviewed_gates(self):
  import hashlib
  from test_quest_import_common import gold_bui_manifest
  from quest_import_common import load_quest_module
  spec=gold_bui_manifest()
  spec['world']={'time_gates':'dream-cave'}
  spec['sources'].update({p:hashlib.sha256((REFERENCE/p).read_bytes()).hexdigest() for p in SOURCES})
  result=load_quest_module(REFERENCE,spec)
  self.assertEqual(result['world']['time_gates'],reviewed_time_gates(self.spec,self.texts))
  spec['sources'][SOURCES[0]]='0'*64
  with self.assertRaises(ValueError):load_quest_module(REFERENCE,spec)
 def test_fail_closed(self):
  for path in SOURCES:
   texts=dict(self.texts);texts.pop(path)
   with self.assertRaises(ValueError):reviewed_time_gates(self.spec,texts)
  with self.assertRaises(ValueError):reviewed_time_gates({'world':{'time_gates':'all'}},self.texts)
  texts=dict(self.texts);texts['gmsv/data/map/mapwarp.txt']=texts['gmsv/data/map/mapwarp.txt'].replace('NONE:A:400,97,119:41,11,8:NULL','NONE:N:400,97,119:41,11,8:NULL')
  with self.assertRaises(ValueError):reviewed_time_gates(self.spec,texts)
  reviewed=reviewed_time_gates(self.spec,self.texts)
  with self.assertRaises(ValueError):apply_time_gates([], [{'time_gates':reviewed}])
  portals=read_portals(REFERENCE/'gmsv/data/npc/genout')
  for p in portals:
   if p.get('source_time_suffix')=='A':p['source_time_suffix']='N'
  with self.assertRaises(ValueError):apply_time_gates(portals,[{'time_gates':reviewed}])
if __name__=='__main__':unittest.main()
