"""Narrow shop source import and mutation rejection; no fire reward dependency."""
import copy
import json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module,merge_quest_module
from quest_jug_shop import SOURCES,SCRIPT,CREATE,IDENT,parse
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
def manifest():
 s=json.loads((ROOT/'tools/transmigration_fire_quest_sources.json').read_text())
 s.update(sources={**{k:v for k,v in s['sources'].items() if k in ['gmsv/data/itemset.txt','gmsv/data/jobdaily.txt']},**SOURCES},creates=[CREATE],scripts={},handlers={SCRIPT:{'kind':'original_jug_shop','events':[40]}},items=[2708],jobs=[],reward_enemies=[])
 for k in ['world','combat_audit','single_item_pile_reviews']:s.pop(k,None)
 return s
class JugShopTests(unittest.TestCase):
 def test_actual_shop(self):
  m=load_quest_module(REF,manifest());n=m['npcs'][0]
  self.assertEqual(n['id'],IDENT);self.assertEqual(n['source_create_index'],41)
  self.assertEqual(n['purchase'],{'item_id':2708,'quantity':1,'price':1150,'base_cost':500,'buy_rate':'2.3'})
  self.assertEqual(n['branches'],[])
 def test_source_and_identity_mutations(self):
  for field,value in [('id','other'),('items',[])]:
   s=manifest();s[field]=value
   with self.assertRaises(ValueError):load_quest_module(REF,s)
  for path in SOURCES:
   s=manifest();s['sources'][path]='0'*64
   with self.assertRaises(ValueError):load_quest_module(REF,s)
 def test_plan_definition_cannot_be_forged_at_merge(self):
  m=load_quest_module(REF,manifest())
  baseline={'npcs':[],'items':{},'jobs':[],'reward_pets':{},'provenance':{}}
  self.assertEqual(merge_quest_module(baseline,m)['npcs'][0]['id'],IDENT)
  for field,value in [('price',1149),('quantity',2),('item_id',2709)]:
   wrong=copy.deepcopy(m);wrong['npcs'][0]['purchase'][field]=value
   with self.assertRaises(ValueError):merge_quest_module(baseline,wrong)
if __name__=='__main__':unittest.main()
