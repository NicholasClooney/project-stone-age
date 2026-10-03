"""Pinned source fixtures for arrival policy tests; never enables a descriptor.

These are complete source data used to create isolated test catalogs, not the
independent public-NPC union oracle. Raw field checks retain source semantics.
"""
import json
import re
import unittest
from pathlib import Path
from quest_import_common import load_quest_module

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'references/chenmingbiao-stone-age'

class EarthFixture(unittest.TestCase):
    def test_locked_source_fixture(self):
        frozen = json.loads((ROOT / 'client/tests/fixtures/transmigration-earth-source.json').read_text())
        actual = load_quest_module(REF, ROOT / 'tools/transmigration_earth_quest_sources.json')
        self.assertEqual(frozen, actual)
        self.assertEqual(len(frozen['npcs']), 11)
        self.assertEqual(len(frozen['items']), 99)
        scripts = {n['source_script']: n for n in frozen['npcs']}
        core = scripts['jaruga/event/ruri01']['branches'][0]
        self.assertEqual(core['actions'], {'DelItem':'2698,2699','GetItem':'2701','Charm':'1','EndSetFlg':'39'})
        for name in ['ruri05', 'ruri06']:
            raw = (REF / ('gmsv/data/npc/jaruga/event/' + name)).read_bytes().decode('gb18030')
            original = re.search(r'^GetRandItem:(.*)$', raw, re.M)[1].strip()
            branch = scripts['jaruga/event/' + name]['branches'][0]
            self.assertEqual(branch['actions']['GetRandItem'], original)
            slots = list(map(int, original.split(',')))
            self.assertEqual(len(slots), 85)
            self.assertEqual(slots[56], 957)
            self.assertEqual(slots.count(957), 2)
            self.assertEqual(branch['condition'], 'LV>0&ITEM=2700')
            self.assertEqual(branch['actions']['DelItem'], '2700')
        raw = frozen['items']['957']['raw_columns']
        self.assertEqual((int(raw[18]), int(raw[22])), (8096, 30))
        self.assertEqual(scripts['200/sb_dbt.arg']['branches'][0]['actions']['Warp'], '21015,9,17')
        self.assertEqual(scripts['200/sb_dtp.arg']['branches'][0]['actions']['Warp'], '21009,45,48')
        for entry in ['genout/wpm_200_359_671', 'genout/wpm_200_358_671']:
            self.assertEqual(scripts[entry]['branches'][0]['condition'], 'LV>64&ENDEV=4')
            self.assertEqual(scripts[entry]['branches'][0]['actions']['Warp'], '21001,4,3')

    def test_independent_original_route(self):
        frozen = json.loads((ROOT / 'client/tests/fixtures/transmigration-earth-route.json').read_text())
        reviewed = json.loads((ROOT / 'docs/reverse-engineering/transmigration-routes.json').read_text())
        self.assertEqual(frozen, next(r for r in reviewed if r['chain'] == 'earth'))
        self.assertEqual(frozen['start'], [21001,4,3])
        self.assertEqual(frozen['goal'], [21015,10,8])
        self.assertEqual(frozen['route'][-1]['source'], '200/sb_dbt.arg')
        self.assertEqual(frozen['route'][-1]['target'], [9,17])

if __name__ == '__main__':
    unittest.main()
