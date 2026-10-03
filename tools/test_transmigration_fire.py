"""Actual fire40 source binding, branch-order and complete random-pool review."""
import copy
import json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
MANIFEST=ROOT/'tools/transmigration_fire_quest_sources.json'
PREFIX='giiru/event/sink/'

class FireTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module=load_quest_module(REF,MANIFEST)
    def source(self,name):
        return next(n for n in self.module['npcs'] if n['source_script']==PREFIX+name)
    def test_committed_fixture_matches_reviewed_source(self):
        fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-fire-source.json').read_text())
        self.assertEqual(fixture,self.module)
    def test_exact_bindings_and_scope(self):
        npcs=self.module['npcs']
        self.assertEqual(len(npcs),19)
        self.assertEqual([(n['map_id'],n['cell']) for n in npcs if n['source_script']==PREFIX+'sink06'],[(30016,[29,36]),(30016,[23,36])])
        for name,mid,cell in [('sink044',30008,[30,69]),('sink044a',30008,[80,14]),('sink044b',30008,[84,19]),('sink044c',30011,[32,34]),('sink055',30012,[7,4]),('sink055a',30001,[38,5])]:
            npc=self.source(name);self.assertEqual((npc['map_id'],npc['cell']),(mid,cell))
        self.assertEqual([b['source_branch_index'] for b in self.source('sink02')['branches']],[0,6,7,8,9,10,11])
        self.assertEqual(self.module['jobs'][0]['event'],40)
        self.assertNotIn('32021',self.module['world']['map_sources'])
    def test_water_and_refund_source(self):
        branches=self.source('sink03')['branches']
        self.assertEqual(branches[0]['actions'],{'DelItem':'2708','GetStone':'1149'})
        self.assertEqual([(b['spoken_keyword'],b['actions']['GetItem']) for b in branches if 'spoken_keyword' in b],[('很多','2709'),('一半','2710'),('一点点','2711')])
        for short in ['sink044','sink044a','sink044b','sink044c']:
            branches=self.source(short)['branches']
            self.assertEqual([(b['actions'].get('DelItem'),b['actions'].get('GetItem')) for b in branches[:3]],[('2709','2716'),('2712','2717'),('2713','2718')])
            self.assertEqual(branches[3]['actions']['GetItem'],'2708')
            self.assertTrue(branches[3]['actions']['DelItem'].endswith(','))
        for short in ['sink055','sink055a']:
            branches=self.source(short)['branches']
            self.assertEqual([b['actions'].get('GetItem') for b in branches[:10]],list(map(str,[2712,2715,2716,2713,2714,2715,2716,2717,2718,2708])))
    def test_full_reward_pools_and_priority(self):
        branches=self.source('sink06')['branches']
        self.assertTrue(all(b['type']=='MESSAGE' for b in branches[:3]))
        self.assertEqual([b['actions']['GetRandItem'] for b in branches[3:10]],[
            '1352,1466,2566','1451,2567,11865','1165,2568,11907,2614','1052,1269,11836,2565',
            '2692,2695,251,562','2693,2696,256,459,1460','2691,2694,65,266,364,971'])
        for i,b in enumerate(branches[3:10],2712):
            self.assertEqual(b['condition'],f'LV>0&ITEM={i}')
            self.assertEqual(b['actions']['DelItem'],str(i))
            self.assertNotIn('EndSetFlg',b['actions'])
            for item in b['actions']['GetRandItem'].split(','):
                self.assertIn(item,self.module['items'])
                self.assertIn('effects',self.module['items'][item])
    def test_guards_and_gate_conditions(self):
        guards=[n for n in self.module['npcs'] if n['branches'] and n['branches'][0]['type']=='BATTLE']
        self.assertEqual(len(guards),3)
        self.assertTrue(all(len(n['branches'][0]['guard']['enemy_ids'])==10 for n in guards))
        gates=[n for n in self.module['npcs'] if n['source_script'].startswith('genout/wpm_')]
        self.assertEqual(len(gates),3)
        self.assertTrue(all(n['branches'][0]['condition']=='LV>64&ENDEV=4' for n in gates if '20301' not in n['source_script']))
    def test_mutated_review_fails_closed(self):
        spec=json.loads(MANIFEST.read_text());spec['scripts'][PREFIX+'sink02']['branches']=[0,2]
        with self.assertRaises(ValueError):load_quest_module(REF,spec)
        spec=json.loads(MANIFEST.read_text());spec['items'].remove(11865)
        with self.assertRaises(ValueError):load_quest_module(REF,spec)

if __name__=='__main__':unittest.main()
