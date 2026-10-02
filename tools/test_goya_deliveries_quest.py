"""Pinned original Goya branches, quantities, pet identity and item numbers."""
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
class GoyaSourceTests(unittest.TestCase):
    def test_actual_bindings_and_pet_branches(self):
        d=load_quest_module(ROOT/'references/chenmingbiao-stone-age',ROOT/'tools/goya_deliveries_quest_sources.json')
        by={n['source_script']:n for n in d['npcs']}
        self.assertEqual(len(by),12)
        boy=by['jaruga/event/event06_1'];merchant=by['jaruga/event/event06_2']
        self.assertEqual((boy['map_id'],boy['cell']),(20401,[12,13]))
        self.assertEqual((merchant['map_id'],merchant['cell']),(4000,[71,97]))
        self.assertEqual([b['condition'] for b in boy['branches']],['NOWEV=6&ITEM=2414*2','NOWEV=6&ITEM=2414*1','LV>0'])
        self.assertEqual([b['actions']['GetPet'] for b in boy['branches'][:2]],['44','47'])
        self.assertTrue(all(b['actions']['DelItem']=='2414*1' and b['actions']['EndSetFlg']=='6' for b in boy['branches'][:2]))
        self.assertEqual([(d['reward_pets'][str(i)]['template_id'],d['reward_pets'][str(i)]['level']) for i in [44,47]],[(63,1),(72,1)])
        self.assertEqual(merchant['branches'][0]['actions'],{'GetItem':'2414*2'})
        self.assertEqual(merchant['branches'][2]['actions'],{'GetItem':'2414'})
        self.assertEqual(merchant['branches'][3]['condition'],'ENDEV=6&ITEM!=2414')
        self.assertEqual(merchant['branches'][3]['event'],-1)
        self.assertEqual(merchant['branches'][3]['actions'],{'GetItem':'2414*1'})
        flower=by['jaruga/event/event07_3']['branches'][0]
        self.assertEqual(flower['actions'],{'GetItem':'2424'})
        self.assertEqual(by['jaruga/event/event07_2']['branches'][0]['actions'],{'DelItem':'2425,2424','EndSetFlg':'7'})
        self.assertEqual(by['jaruga/event/event07_1']['branches'][0]['actions'],{'GetItem':'1206','DelItem':'2426','EndSetFlg':'8'})
        self.assertEqual([j['event'] for j in d['jobs']],[6,7,8])
        self.assertEqual({e for n in d['npcs'] for e in n['events']},{8, 6, 7})
        self.assertFalse(any(47 in n['events'] or any(b['event']==47 for b in n['branches']) for n in d['npcs']))
        bracelet=d['items']['1206']
        self.assertEqual(bracelet['raw_columns'][37:43],['3','3','3','3','-3','-3'])
        self.assertEqual(bracelet['raw_columns'][49:51],['2','2'])
        self.assertIn('原字段不一致',bracelet['description'])
        self.assertTrue(all(n['graphic'] in [100250,100252] for n in d['npcs'] if 'event07_' in n['source_script']))
if __name__=='__main__':unittest.main()
