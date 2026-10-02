"""Original create, branch order and the two same-named axe definitions."""
from pathlib import Path
import unittest
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]

class YamAxeSourceTests(unittest.TestCase):
    def test_original_chain_and_rewards(self):
        data=load_quest_module(ROOT/'references/chenmingbiao-stone-age', ROOT/'tools/yam_axe_quest_sources.json')
        self.assertEqual([(n['source_script'],n['map_id'],n['cell']) for n in data['npcs']], [('sainasu/event/event03_2',1400,[69,89]),('sainasu/event/event03_1',1300,[18,42])])
        yam,mati=data['npcs']
        self.assertEqual(yam['branches'][0]['actions'],{'GetItem':'2448','DelItem':'2423','EndSetFlg':'5'})
        self.assertEqual(yam['branches'][1]['actions'],{'GetItem':'2416'})
        self.assertEqual(mati['branches'][0]['actions'],{'DelItem':'2416','EndSetFlg':'3'})
        self.assertEqual(mati['branches'][0]['condition'],'NOWEV=3&ITEM=2416')
        self.assertEqual(mati['branches'][1]['condition'],'ENDEV=3')
        self.assertEqual(mati['branches'][1]['actions'],{'GetItem':'2423'})
        self.assertEqual([j['event'] for j in data['jobs']],[3,5])
        self.assertEqual({e for n in data['npcs'] for e in n['events']},{3, 5})
        self.assertFalse(any(47 in n['events'] or any(b['event']==47 for b in n['branches']) for n in data['npcs']))
        first,last=[data['items'][str(i)] for i in (2416,2448)]
        self.assertEqual(first['raw_columns'][19:23],['1','0','0','20'])
        self.assertEqual(last['raw_columns'][19:23],['1','0','0','25'])
        self.assertEqual(first['raw_columns'][78:80],['0','1'])
        self.assertEqual(last['raw_columns'][78:80],['0','0'])
        self.assertEqual(first['raw_columns'][37:43],['9','9','-3','-3','-3','-3'])
        self.assertEqual(last['raw_columns'][37:43],['35','35','-10','-10','-10','-10'])
        self.assertIn('交给马提前须卸下',first['description'])
        self.assertIn('尚无地面拾取',last['description'])

if __name__=='__main__':unittest.main()
