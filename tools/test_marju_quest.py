"""Pinned actual mail route; bag services are deliberately not selected."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
SPEC=ROOT/'tools/marju_quest_sources.json'
class MarjuSourceTests(unittest.TestCase):
 def test_actual_binding_branches_items(self):
  data=load_quest_module(REF,SPEC)
  mail,recipient=[n for n in data['npcs'] if n['source_script'].startswith('extra/event/')]
  self.assertEqual([(n['map_id'],n['cell']) for n in [mail,recipient]],[(1300,[70,51]),(119,[97,88])])
  self.assertEqual(mail['branches'][0]['condition'],'LV>49&ENDEV!=38')
  self.assertEqual(mail['branches'][1]['actions'],{'GetRandItem':'2688,2689,2690','EndSetFlg':'38'})
  self.assertEqual(recipient['branches'][0]['condition'],'NOWEV=37&LV>49&ITEM=2687&ITEM!=2697')
  self.assertEqual(recipient['branches'][0]['actions'],{'DelItem':'2687','GetItem':'2697','EndSetFlg':'37'})
  self.assertEqual(recipient['branches'][0]['event'],38)
  self.assertEqual(recipient['branches'][2]['condition'],'NOWEV!=37&ENDEV!=37&LV>39&ITEM!=2697')
  self.assertEqual([j['event'] for j in data['jobs']],[37,38])
  self.assertEqual(set(data['items']),{'2687','2688','2689','2690','2697'})
  self.assertFalse(any('marju02' in n['id'] for n in data['npcs']))
  for ident,stats,magic in [(2688,['50','50','-20','-20','-20','-20'],['12','100','16']),(2689,['45','45','0','0','-10','-10'],['2','100','11']),(2690,['35','35','0','0','0','0'],['22','100','40'])]:
   raw=data['items'][str(ident)]['raw_columns']
   self.assertEqual(raw[37:43],stats)
   self.assertEqual(raw[55:58],magic)
   self.assertEqual(raw[22],'50')
 def test_source_and_maps_pinned(self):
  spec=json.loads(SPEC.read_text())
  for path,sha in spec['sources'].items():self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),sha)
  for entry in spec['world']['map_sources'].values():self.assertEqual(hashlib.sha256((REF/entry['path']).read_bytes()).hexdigest(),entry['sha256'])
  invalid=copy.deepcopy(spec);invalid['sources']['gmsv/data/itemset.txt']='0'*64
  with self.assertRaises(ValueError):load_quest_module(REF,invalid)
  gate=(REF/'gmsv/data/npc/genout/wpm_120_19_15').read_text(encoding='gb18030')
  for clause in ['WARP:122,6,5','FREE:LV>49','MONEY:-1','PartyMsg:']:self.assertIn(clause,gate)
if __name__=='__main__':unittest.main()
