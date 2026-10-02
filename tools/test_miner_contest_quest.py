"""Actual mining-contest bindings, transactions and original drop evidence."""
import copy
import json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/'references/chenmingbiao-stone-age'
MANIFEST=ROOT/'tools/miner_contest_quest_sources.json'
class MinerSourceTests(unittest.TestCase):
 def test_original_branches_and_guard(self):
  module=load_quest_module(REFERENCE,MANIFEST)
  npcs={n['source_script']:n for n in module['npcs']}
  leader=npcs['giiru/event/giruev2_1']
  self.assertEqual((leader['map_id'],leader['cell']),(31805,[19,21]))
  self.assertEqual([b['source_branch_index'] for b in leader['branches']],[0,1,2,3])
  self.assertEqual(leader['branches'][0]['condition'],'ENDEV=27&ITEM!=2391')
  self.assertEqual(leader['branches'][0]['actions'],{'GetItem':'2527','DelStone':'1000'})
  self.assertEqual(leader['branches'][1]['actions'],{'GetItem':'2527','DelItem':'2533','EndSetFlg':'27'})
  self.assertEqual(leader['branches'][3]['condition'],'LV>29&ENDEV!=27')
  rival=npcs['giiru/event/giruev2_2']
  self.assertEqual(rival['branches'][3]['actions'],{'GetItem':'2535','DelItem':'2534*1,2536'})
  self.assertEqual(rival['branches'][5]['actions'],{'GetItem':'2536*1'})
  guard=npcs['300/sb_bac.arg']['branches'][0]
  self.assertEqual(guard['guard'],{'enemy_ids':[1004],'dieact':0,'required_items':[2535],'steal':1,'cooldown':300})
  self.assertEqual(guard['actions'],{'Battle':'1004'})
  self.assertEqual(len(next(iter(guard['combat_audit']['bases'].values()))['skills']),7)
  self.assertEqual({(d['enemy_id'],d['item_id'],d['probability']) for d in module['drops']},{(1043,2534,1000),(1004,2533,1000)})
  self.assertEqual([j['event'] for j in module['jobs']],[27])
  self.assertEqual(set(module['world']['map_sources']),{str(i) for i in range(31801,31807)})
 def test_source_mutation_rejected(self):
  spec=json.loads(MANIFEST.read_text());spec['sources']['gmsv/data/npc/300/sb_bac.arg']='0'*64
  with self.assertRaises(ValueError):load_quest_module(REFERENCE,spec)
 def test_original_conditional_encounter(self):
  import csv
  read=lambda name:list(csv.reader((REFERENCE/'gmsv/data'/name).read_bytes().decode('gb18030').splitlines()))
  group=next(r for r in read('group.txt') if len(r)>4 and r[1]=='508')
  self.assertEqual(group[2],'2536');self.assertIn('1043',group[4:14])
  areas=[r for r in read('encount.txt') if len(r)>10 and r[1] in ['31801','31802','31803']]
  self.assertEqual(len(areas),3);self.assertTrue(all('508' in r[10:20] for r in areas))
if __name__=='__main__':unittest.main()
