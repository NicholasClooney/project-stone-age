"""Actual bound source, conditional groups and every audited enemy skill row."""
import csv,hashlib,json,re
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1];REF=ROOT/'references/chenmingbiao-stone-age'
class FourJewelsSourceTests(unittest.TestCase):
 def test_actual_bound_source_and_drops(self):
  spec=json.loads((ROOT/'tools/four_jewels_quest_sources.json').read_text())
  data=load_quest_module(REF,spec)
  self.assertEqual(len(data['npcs']),1)
  self.assertEqual(len(data['drops']),4)
  self.assertEqual(data['npcs'][0]['branches'][0]['actions']['EndSetFlg'],'45')
  self.assertEqual(data['npcs'][0]['branches'][0]['actions']['NpcWarp'],'4000.53.101,2000.44.39,5105.14.3,6000.58.44')
  for path,sha in spec['sources'].items():self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),sha)
  self.assertEqual(list(spec['scripts']),['extra/event/hougyoku'])
  text=(REF/'gmsv/data/npc/extra/event/hougyoku').read_text(encoding='gb18030')
  self.assertIn('EVENT:LV>59&ITEM=2764&ITEM=2760&ITEM=2761&ITEM=2762&ITEM=2763',text)
  self.assertIn('NpcWarp:4000.53.101,2000.44.39,5105.14.3,6000.58.44',text)
  create=(REF/spec['creates'][0]).read_text(encoding='gb18030')
  self.assertIn('enemy=changeevent|file:extra/event/hougyoku',create)
  self.assertIn('floorid=6000',create);self.assertIn('borncorner=58,44,58,44',create)
  enemies={int(r[3]):r for r in csv.reader((REF/'gmsv/data/enemy.txt').read_text(encoding='gb18030').splitlines()) if len(r)>3 and r[3].isdigit()}
  for drop in spec['drops']:
   row=enemies[drop['enemy_id']]
   self.assertEqual((int(row[14]),int(row[24])),(drop['item_id'],drop['probability']))
  self.assertEqual([(d['enemy_id'],d['item_id'],d['probability']) for d in spec['drops']],[(1305,2760,100),(1306,2761,500),(1307,2763,500),(1308,2762,100)])
  groups={int(r[1]):r for r in csv.reader((REF/'gmsv/data/group.txt').read_text(encoding='gb18030').splitlines()) if len(r)>1 and r[1].isdigit()}
  for ident,item in [(711,2760),(712,2761),(713,2763),(714,2762)]:self.assertEqual(groups[ident][2:4],['2764',str(item)])
  report=(ROOT/'docs/reverse-engineering/four-jewels-quest.md').read_text()
  for ident in range(1305,1318):self.assertIn(enemies[ident][1].replace('|',r'\|'),report)
if __name__=='__main__':unittest.main()
