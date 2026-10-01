"""Source parsing, reviewed packet and map ownership regression checks."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import import_early_quests as quests
import plan_web_packs as packs

REFERENCE = Path(__file__).resolve().parents[1]/'references/chenmingbiao-stone-age'


class EarlyQuestTests(unittest.TestCase):
    def test_real_packet(self):
        data = quests.catalog(REFERENCE)
        self.assertEqual(set(data['items']), {'2414', '2415'})
        self.assertEqual(data['items']['2414']['logical_icon'], 24130)
        self.assertEqual(data['items']['2415']['name'], '仙尼亚的花')
        self.assertFalse(data['items']['2415']['stackable'])
        self.assertEqual([(n['map_id'], n['cell']) for n in data['npcs']], [(2000, [55,92]), (1000, [57,124])])
        npc = data['npcs'][0]
        self.assertEqual([b['type'] for b in npc['branches']], ['CLEAN', 'ACCEPT', 'REQUEST'])
        self.assertEqual(npc['branches'][1]['actions'], {'GetItem':'2414','DelItem':'2415','EndSetFlg':'2'})
        self.assertIn('\n', npc['branches'][2]['texts']['ThanksMsg'])
        self.assertNotIn('\\n', npc['branches'][2]['texts']['ThanksMsg'])
        self.assertEqual(data['jobs'][0]['title'], '不可思议的贝壳')

    def test_changed_sources_rejected(self):
        spec = json.loads(quests.SPEC.read_text())
        spec['sources'][spec['create']] = '0'*64
        with self.assertRaisesRegex(ValueError, 'Unreviewed source'):
            quests.catalog(REFERENCE, spec)

    def test_unsupported_scripts_rejected(self):
        for text in ['EventNo:2\nTYPE:WARP\nEVENT:LV>0\nEventEnd',
                     'EventNo:2\nTYPE:REQUEST\nEVENT:GOLD=2\nEventEnd',
                     'EventNo:2\nTYPE:REQUEST\nEVENT:LV>0\nGetGold:3\nEventEnd',
                     'EventNo:2\nTYPE:REQUEST\nEVENT:LV>0']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                quests.parse_script(text)

    def test_map_pack_ownership(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def write(path, data):
                target = root/path; target.parent.mkdir(parents=True,exist_ok=True)
                target.write_text(json.dumps(data))
            write('world/manifest.json', {'maps':{'1000':{'path':'world/1000.map'},'2000':{'path':'world/2000.map'}},'residents':[]})
            write('world/1000.map', {}); write('world/2000.map', {})
            write('characters/catalog.json', {}); write('battle/manifest.json', {})
            write('quests/catalog.json', {'npcs':[{'path':'quests/npcs/a.png','map_id':1000},{'path':'quests/npcs/b.png','map_id':2000}]})
            for path in ['quests/npcs/a.png','quests/npcs/b.png','quests/items/2414.png','quests/items/2415.png']:
                write(path,{})
            with patch.object(packs, 'LEGACY', root), patch.object(packs, 'load_map', return_value={'images':{}}):
                plan = packs.plan()
            self.assertIn(packs.RES+'quests/npcs/a.png', plan['packs']['map-1000'])
            self.assertIn(packs.RES+'quests/npcs/b.png', plan['packs']['map-2000'])
            self.assertIn(packs.RES+'quests/catalog.json', plan['packs']['core'])
            self.assertIn(packs.RES+'quests/items/2414.png', plan['packs']['core'])
            all_files = [p for files in plan['packs'].values() for p in files]
            self.assertEqual(len(all_files), len(set(all_files)))

if __name__ == '__main__':
    unittest.main()
