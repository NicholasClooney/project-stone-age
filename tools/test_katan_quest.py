"""Actual region-bound four-shark chain and pinned source collision."""
import csv,hashlib,json
from pathlib import Path
import unittest
from import_early_quests import parse_script
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'references/chenmingbiao-stone-age'
class KatanSourceTests(unittest.TestCase):
 def test_source_scope_exact_pairs_and_reward(self):
  spec=json.loads((ROOT/'tools/katan_quest_sources.json').read_text())
  for path,sha in spec['sources'].items():self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),sha)
  selection=spec['scripts']['seimu/event/event02_1']
  self.assertEqual(selection['branches'],[0,1,2,3])
  source=(REF/'gmsv/data/npc/seimu/event/event02_1').read_text(encoding='gb18030')
  _,branches=parse_script(source,selection['branches'])
  self.assertEqual([b['source_line'] for b in branches],[3,15,22,32])
  self.assertEqual(branches[0]['actions'],{'DelPet':'PET=25-221*1,PET=25-222*1','DelItem':'2607','GetPet':'93','EndSetFlg':'35'})
  self.assertEqual(branches[2]['actions'],{'DelPet':'PET=25-223*1,PET=25-224*1','GetItem':'2607'})
  self.assertEqual(branches[3]['condition'],'LV>0&ENDEV!=35')
  data=load_quest_module(REF,spec)
  self.assertEqual(len(data['npcs']),1)
  npc=data['npcs'][0]
  self.assertEqual(npc['id'],'seimu/event/event02_1@100:230:180:area:525:200')
  self.assertEqual(npc['source_spawn']['rect'],[230,180,525,200])
  self.assertEqual(len(npc['source_spawn']['walkable']),6216)
  self.assertEqual(npc['source_spawn']['walkable'].count('1'),6125)
  self.assertEqual(data['reward_pets']['93']['template_id'],171)
  self.assertEqual(data['reward_pets']['93']['level'],1)
  self.assertEqual(data['items']['2607']['name'],'火难的戒指')
  create=(REF/spec['creates'][0]).read_text(encoding='gb18030')
  self.assertIn('borncorner=230,180,525,200',create)
  self.assertEqual(selection['spawn_policy'],{'mode':'source-area'})
  report=(ROOT/'docs/reverse-engineering/katan-quest.md').read_text()
  for line,row in enumerate(csv.reader((REF/'gmsv/data/enemy.txt').read_text(encoding='gb18030').splitlines()),1):
   if len(row)>13 and row[3].isdigit() and (row[3]=='93' or (row[4] in {'221','222','223','224'} and row[13]=='1' and max(int(row[5]),int(row[6]))<=25)):
    self.assertIn(f"| {line} / {row[3]} / {row[4]} /",report)
    self.assertIn(row[1].replace('|',r'\|'),report)
if __name__=='__main__':unittest.main()
