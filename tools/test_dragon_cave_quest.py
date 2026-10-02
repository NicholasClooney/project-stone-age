"""Actual END17 source binding, three gated drops and mutually exclusive rewards."""
import csv
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/'references/chenmingbiao-stone-age'
class DragonSourceTests(unittest.TestCase):
 def test_bound_source_choices(self):
  m=load_quest_module(REFERENCE,ROOT/'tools/dragon_cave_quest_sources.json')
  by={n['source_script']:n for n in m['npcs']}
  self.assertEqual(len(by),5)
  for i,reward in [(1,2462),(2,2460),(3,2461)]:
   b=by[f'jaruga/event/event17_{i}']['branches'][0]
   self.assertEqual(b['condition'],'NOWEV=17&ITEM=2457&ITEM=2458&ITEM=2459&ITEM=2505')
   self.assertEqual(b['actions'],{'GetItem':str(reward),'DelItem':'2457,2458,2459,2505','EndSetFlg':'17'})
  guard=by['genout/wpm_20807_11_37']['branches'][0]
  self.assertEqual(guard['condition'],'ITEM=2457&ITEM=2458&ITEM=2459')
  self.assertEqual(guard['actions'],{'Warp':'20807,13,35'})
  self.assertEqual({(d['enemy_id'],d['item_id'],d['probability']) for d in m['drops']},{(562,2457,800),(560,2458,800),(559,2459,800)})
 def test_original_groups_and_equipment_columns(self):
  def rows(name):return list(csv.reader((REFERENCE/'gmsv/data'/name).read_bytes().decode('gb18030').splitlines()))
  groups={r[1]:r for r in rows('group.txt') if len(r)>14}
  for group,enemy in [('404','562'),('405','560'),('406','559')]:
   self.assertEqual(groups[group][2],'2505');self.assertIn(enemy,groups[group][4:14])
  items={r[16]:r for r in rows('itemset.txt') if len(r)>78}
  self.assertEqual(items['2460'][37:43],['36','36','-14','-14','-14','-14'])
  self.assertEqual(items['2460'][49:51],['2','2'])
  self.assertEqual(items['2505'][49:51],['3','3'])
  self.assertEqual(items['2460'][19:23],['3','0','0','40'])
  self.assertEqual(items['2505'][19:23],['9','0','0','40'])
if __name__=='__main__':unittest.main()
