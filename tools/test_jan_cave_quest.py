"""Pinned original Jan branch, guard and portal contracts."""
import csv
import hashlib
import json
import re
import unittest
from pathlib import Path
from quest_import_common import load_quest_module

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'references/chenmingbiao-stone-age'

def exchanges_only(name):
    spec = json.loads((ROOT / f'tools/{name}_cave_quest_sources.json').read_text())
    spec['handlers'] = {}  # Test exchange subset; never register incomplete chains.
    return load_quest_module(REFERENCE, spec)

class JanSourceTests(unittest.TestCase):
    def test_jan_reward_is_22_before_letter_21_and_no_161(self):
        data = exchanges_only('jan')
        fixture = json.loads((ROOT / 'client/tests/fixtures/jan-cave-exchanges.json').read_text())
        self.assertEqual(fixture['npcs'], data['npcs'])
        self.assertEqual(fixture['items'], data['items'])
        by = {n['source_script'].rsplit('/', 1)[-1]: n for n in data['npcs']}
        self.assertEqual(len(by), 6)
        world = data['world']
        self.assertEqual(set(world['map_sources']), {str(i) for i in range(20601, 20609)})
        choice = world['portal_choices'][0]
        self.assertEqual((choice['from_map'], choice['cell'], choice['to_map'], choice['to_cell']),
                         (20607, [75, 13], 20608, [0, 7]))
        rows = (REFERENCE / 'gmsv/data/map/mapwarp.txt').read_bytes().decode('gb18030').splitlines()
        choices = [r.split(':')[3] for r in rows if r.startswith('NONE:NULL:20607,75,13:')]
        self.assertEqual(choices, ['20608,0,7', '20608,0,8'])
        self.assertIn('NONE:NULL:20608,0,7:20607,75,13:NULL', rows)
        self.assertIn('NONE:NULL:20608,0,8:20607,75,13:NULL', rows)
        self.assertEqual((by['event20_6']['map_id'], by['event20_6']['cell']), (20608, [9, 3]))
        reward = by['event20_4']['branches'][1]
        self.assertEqual(reward['condition'], 'ENDEV=20&NOWEV=21')
        self.assertEqual(reward['actions'], {'GetRandItem': '2490,2491,2492,2493,2494', 'EndSetFlg': '22'})
        letter = by['event20_6']['branches'][0]
        self.assertEqual(letter['condition'], 'NOWEV=21&ENDEV=22&ITEM!=2488')
        self.assertEqual(by['event20_2']['branches'][0]['actions'],
                         {'DelItem': '2488', 'GetItem': '2489', 'EndSetFlg': '21'})
        self.assertEqual({e for n in by.values() for e in n['events']}, {20, 21, 22})
        self.assertFalse(any('NOWEV=161' in b['condition'] for n in by.values() for b in n['branches']))

    def test_complete_module(self):
        spec = json.loads((ROOT / 'tools/jan_cave_quest_sources.json').read_text())
        data = load_quest_module(REFERENCE, spec)
        self.assertEqual(len(data['npcs']), 12)
        self.assertEqual({e for n in data['npcs'] for e in n['events']}, {20, 21, 22})
        self.assertEqual(data.get('drops', []), [])
        self.assertEqual(set(spec['world']['restored_scripts']), set(spec['handlers']))
        guards = [n for n in data['npcs'] if n['branches'][0].get('guard')]
        self.assertEqual(len(guards), 3)
        for npc in guards:
            self.assertEqual(npc['branches'][0]['guard'], {'enemy_ids': [961, 963, 962], 'dieact': 1})
            self.assertEqual(npc['branches'][0]['actions'], {'Battle': '961,963,962', 'Warp': '20607,36,31'})
        gates = [n for n in data['npcs'] if n['branches'][0]['type'] == 'KEYWORD']
        self.assertEqual([n['branches'][0]['keyword'] for n in gates],
                         ['红色月亮的光芒', '蓝色山脉即力量', '白色之风即速度'])
        for record in spec['world']['map_sources'].values():
            self.assertEqual(hashlib.sha256((REFERENCE / record['path']).read_bytes()).hexdigest(), record['sha256'])
        audit = spec['combat_audit']
        self.assertEqual(hashlib.sha256((ROOT / audit['path']).read_bytes()).hexdigest(), audit['sha256'])

if __name__ == '__main__':
    unittest.main()
