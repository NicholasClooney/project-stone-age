"""Source-only contract evidence for forthcoming cave NPC handlers."""
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

class SatonSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / "docs/reverse-engineering/bonus-cave-chains-sources.json").read_text())

    def test_saton_clean_is_original_and_not_supplemental_14(self):
        data = exchanges_only('saton')
        fixture = json.loads((ROOT / 'client/tests/fixtures/saton-cave-exchanges.json').read_text())
        self.assertEqual(fixture['npcs'], data['npcs'])
        self.assertEqual(fixture['items'], data['items'])
        scripts = {n['source_script']: n for n in data['npcs']}
        self.assertEqual(len(scripts), 2)
        main = scripts['sainasu/event/event13_1']['branches'][0]
        self.assertEqual(main['source_actions'], {'GetItem': '2450', 'DelItem': '2428,2429,2430,2431', 'EndSetFlg': '13'})
        self.assertEqual(main['actions']['EndSetFlg'], '13,14')
        self.assertEqual(main['project_supplement']['end_flags_add'], [14])
        clean = scripts['sainasu/event/event13_2']['branches'][0]
        self.assertEqual((clean['type'], clean['condition'], clean['actions']), ('CLEAN', 'ENDEV=13', {'CleanFlg': '13'}))
        self.assertIn('authorized', self.evidence['blocking_decisions'][0]['status'])
        # Supplemental 14 must come from separately audited metadata, never fake source text.
        self.assertEqual(main['source_line'], 9)
        self.assertEqual(clean['source_actions'], {'CleanFlg': '13'})
        self.assertIn('加点项14保留', clean['confirmation_text'])


    def test_original_guards_and_guaranteed_drops(self):
        spec = json.loads((ROOT / 'tools/saton_cave_quest_sources.json').read_text())
        data = load_quest_module(REFERENCE, spec)
        self.assertEqual(len(data['npcs']), 5)
        self.assertEqual({e for n in data['npcs'] for e in n['events']}, {13, 14})
        self.assertEqual({(d['enemy_id'], d['item_id'], d['probability']) for d in data['drops']},
                         {(513, 2428, 1000), (514, 2429, 1000), (515, 2430, 1000)})
        guards = [n for n in data['npcs'] if n['branches'][0].get('guard')]
        self.assertEqual(len(guards), 3)
        self.assertEqual([n['branches'][0]['guard']['enemy_ids'] for n in guards], [[513, 516], [514, 518], [515, 519]])
        for npc in guards:
            g = npc['branches'][0]['guard']
            self.assertEqual(g['dieact'], 0)
            self.assertEqual(g['required_items'], [2431])
            self.assertEqual(g['cooldown'], 300)
            self.assertEqual(g['steal'], False)
        self.assertEqual(set(spec['world']['map_sources']), {str(i) for i in range(10701, 10706)})
        self.assertEqual(set(spec['world']['restored_scripts']), set(spec['handlers']))
        for record in spec['world']['map_sources'].values():
            self.assertEqual(hashlib.sha256((REFERENCE / record['path']).read_bytes()).hexdigest(), record['sha256'])

if __name__ == '__main__':
    unittest.main()
