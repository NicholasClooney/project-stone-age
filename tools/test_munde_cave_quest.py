"""Pinned original Munde exchange order; draft is not activation approval."""
import unittest
import json
from pathlib import Path
from quest_import_common import load_quest_module

ROOT = Path(__file__).resolve().parents[1]

class MundeSourceTests(unittest.TestCase):
    def test_complete_guards_drops_and_world(self):
        import hashlib
        spec = json.loads((ROOT / 'tools/munde_cave_quest_sources.json').read_text())
        data = load_quest_module(ROOT / 'references/chenmingbiao-stone-age', spec)
        self.assertEqual(len(data['npcs']), 7)
        self.assertEqual({e for n in data['npcs'] for e in n['events']}, {9, 10, 11, 12})
        self.assertEqual({(d['enemy_id'], d['item_id'], d['probability']) for d in data['drops']}, {(526, 2482, 10), (527, 2483, 10)})
        guards = [n for n in data['npcs'] if n['branches'][0].get('guard')]
        self.assertEqual(len(guards), 2)
        for npc in guards:
            self.assertEqual(npc['branches'][0]['guard'], {'enemy_ids': [527, 526, 528, 529], 'dieact': 1})
        self.assertEqual(set(spec['world']['restored_scripts']), set(spec['handlers']))
        self.assertEqual(set(spec['world']['map_sources']), {str(i) for i in range(11101, 11108)})
        for record in spec['world']['map_sources'].values():
            self.assertEqual(hashlib.sha256((ROOT / 'references/chenmingbiao-stone-age' / record['path']).read_bytes()).hexdigest(), record['sha256'])

    def test_original_bindings_and_first_completion_order(self):
        spec = json.loads((ROOT / 'tools/munde_cave_quest_sources.json').read_text())
        spec['handlers'] = {}  # Exchange-only unit; guards are covered by the complete module test.
        data = load_quest_module(ROOT / 'references/chenmingbiao-stone-age', spec)
        fixture = json.loads((ROOT / 'client/tests/fixtures/munde-cave-exchanges.json').read_text())
        self.assertEqual(fixture['npcs'], data['npcs'])
        self.assertEqual(fixture['items'], data['items'])
        by = {npc['source_script'].rsplit('/', 1)[-1]: npc for npc in data['npcs']}
        self.assertEqual(set(by), {'event09', 'event10', 'event11', 'event12'})
        self.assertEqual([(by[k]['map_id'], by[k]['cell']) for k in by],
                         [(1200, [97, 75]), (1300, [65, 65]),
                          (1400, [71, 76]), (11107, [24, 6])])
        self.assertEqual({e for n in by.values() for e in n['events']}, {9, 10, 11, 12})
        self.assertFalse(any(b['event'] in [41, 42, 47]
                             for n in by.values() for b in n['branches']))
        self.assertEqual(by['event09']['branches'][1]['condition'], 'LV>29&ENDEV=4')
        first = by['event11']['branches'][1]
        self.assertEqual(first['condition'], 'NOWEV=11&ITEM=2420')
        self.assertEqual(first['actions'], {
            'GetItem': '1052', 'DelItem': '2420', 'EndSetFlg': '11', 'Charm': '1'})
        hotor = by['event10']['branches']
        self.assertEqual(hotor[0]['condition'], 'ENDEV=11&NOWEV=10&ITEM=2419')
        self.assertEqual(hotor[0]['actions'], {
            'GetItem': '2421', 'DelItem': '2419', 'EndSetFlg': '10,12'})
        self.assertEqual(hotor[1]['condition'], 'ENDEV=12&ITEM=2419')
        final = by['event09']['branches'][0]
        self.assertEqual(final['condition'], 'ENDEV=12&ENDEV=10&ENDEV=11')
        self.assertEqual(final['actions'], {'GetItem': '1357', 'EndSetFlg': '9'})
        chief = by['event12']['branches']
        self.assertEqual(len(chief), 1)
        self.assertEqual(chief[0]['source_line'], 4)
        self.assertEqual(chief[0]['condition'], 'NOWEV=9&NOWEV=10&NOWEV=11&ITEM!=2419&ITEM!=2420')
        self.assertEqual(chief[0]['actions'], {'GetItem': '2419,2420'})
        self.assertEqual(set(data['items']), {'1052', '1357', '2419', '2420', '2421', '2482', '2483'})
        self.assertEqual([j['event'] for j in data['jobs']], [9])

if __name__ == '__main__':
    unittest.main()
