"""Earth39 pinned branch/pool evidence and actual import regression."""
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
SPEC=ROOT/'tools/transmigration_earth_quest_sources.json'
class Earth(unittest.TestCase):
 def test_complete_source_pools(self):
  audit=json.loads((ROOT/'docs/reverse-engineering/transmigration-earth-rewards.json').read_text())
  rows={int(r[16]):r for r in csv.reader((REF/'gmsv/data/itemset.txt').read_bytes().decode('gb18030').splitlines()) if len(r)>16 and r[16].isdigit()}
  for script,record in audit['pools'].items():
   raw=(REF/('gmsv/data/npc/jaruga/event/'+script)).read_bytes().decode('gb18030')
   pool=list(map(int,re.search(r'GetRandItem:(.*)',raw)[1].split(',')))
   self.assertEqual(record['slots'],pool);self.assertEqual(len(pool),85)
   self.assertEqual(pool[56],957);self.assertNotIn(95,pool)
   self.assertEqual(record['weights'],{str(k):v for k,v in collections.Counter(pool).items()})
   self.assertEqual(len(record['restored_tail']),28)
   for ident in set(pool):
    slot=audit['items'][str(ident)]
    self.assertEqual(slot['raw_columns'],rows[slot['id']])
    self.assertEqual(slot['cost'],int(rows[slot['id']][18]))
    self.assertEqual(slot['level'],int(rows[slot['id']][22]))
    self.assertTrue(all(not e['active'] for e in slot['effects']))
   self.assertEqual((audit['items']['957']['cost'],audit['items']['957']['level']),(8096,30))
 def test_actual_module(self):
  module=load_quest_module(REF,SPEC)
  self.assertEqual(len(module['npcs']),11)
  scripts={n['source_script']:n for n in module['npcs']}
  self.assertNotIn('jaruga/event/ruri03a',scripts)
  core=scripts['jaruga/event/ruri01']['branches'][0]
  self.assertEqual(core['actions']['DelItem'],'2698,2699')
  self.assertEqual(core['actions']['EndSetFlg'],'39')
  self.assertEqual([b['source_branch_index'] for b in scripts['jaruga/event/ruri01']['branches']],[0,2,3,4,5])
  self.assertEqual(module['drops'][0]['enemy_id'],1146)
  self.assertEqual(module['drops'][0]['probability'],1000)
  for script in ['200/sb_dtp.arg','200/sb_dbt.arg']:
   guard=scripts[script]['branches'][0]
   self.assertEqual(len(guard['guard']['enemy_ids']),10)
   self.assertEqual(guard['combat_audit']['runtime'],'existing-ai-only')
  for script in ['jaruga/event/ruri05','jaruga/event/ruri06']:
   reward=scripts[script]['branches'][0]
   self.assertEqual(len(reward['actions']['GetRandItem'].split(',')),85)
   self.assertEqual(reward['actions']['DelItem'],'2700')
   self.assertEqual(reward['condition'],'LV>0&ITEM=2700')
 def test_only_earth_world_open(self):
  spec=json.loads(SPEC.read_text())
  self.assertEqual(set(spec['world']['map_sources']),set(map(str,range(21001,21016))))
  for record in spec['world']['map_sources'].values():self.assertEqual(hashlib.sha256((REF/record['path']).read_bytes()).hexdigest(),record['sha256'])
  self.assertEqual(json.loads((ROOT/'client/data/quests/transmigration-earth.json').read_text())['enabled_events'],[39])
if __name__=='__main__':unittest.main()
