"""Independent original identities, without runtime catalog/activation as oracle."""
import copy
import hashlib
import json
import re
import unittest
from pathlib import Path
from quest_import_common import load_quest_module
from transmigration_foundation import validate

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'references/chenmingbiao-stone-age'
SPEC = ROOT / 'tools/transmigration_final_quest_sources.json'
FIXTURE = ROOT / 'client/tests/fixtures/transmigration-final-identities.json'

class FinalSources(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(SPEC.read_text())
        self.fixture = json.loads(FIXTURE.read_text())
        self.texts = {p: (REF/p).read_bytes().decode('gb18030') for p in self.spec['sources']}

    def test_exact_create_identities(self):
        self.assertEqual(len(self.fixture['npcs']), 12)
        self.assertEqual(len({a['id'] for a in self.fixture['npcs']}), 12)
        for a in self.fixture['npcs']:
            text = self.texts[a['source_create']]
            block = list(re.finditer(r'\{([^}]+)\}', text))[a['source_create_index']]
            fields = dict(line.strip().split('=', 1) for line in block[1].splitlines()
                          if '=' in line and not line.lstrip().startswith('#'))
            self.assertEqual(fields, a['source_fields'])
            self.assertEqual(text[:block.start()].count('\n')+1, a['source_line'])
            self.assertEqual(fields['enemy'], a['source_handler']+'|file:'+a['source_script'])
            self.assertEqual(int(fields['floorid']), a['map_id'])
            self.assertEqual(list(map(int, fields.get('borncorner', fields.get('borncenter')).split(',')))[:2], a['cell'])
            self.assertEqual([int(fields['graphicname']), int(fields['dir']), fields['name']], [a['graphic'], a['facing'], a['name']])
        king = next(a for a in self.fixture['npcs'] if a['source_script']=='777/ten.arg')
        self.assertEqual((king['source_create_index'], king['map_id'], king['cell'], king['graphic'], king['facing'], king['source_handler']), (5, 32021, [31,28], 100444, 4, 'npc_transmigration'))

    def test_locked_sources_maps_and_mutation(self):
        for path, digest in self.spec['sources'].items():
            self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(), digest, path)
        self.assertEqual(set(self.spec['staged_world']['map_sources']), set(map(str, range(32001,32022))))
        validate(REF, self.spec, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['reviewed_bindings'][0]['cell'][0] += 1
        with self.assertRaisesRegex(ValueError, 'actual create'):
            validate(REF, changed, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['staged_world']['map_sources']['32021']['sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError, 'SHA changed'):
            validate(REF, changed, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['sources']['gmsv/data/npc/777/ten.arg'] = '0'*64
        with self.assertRaisesRegex(ValueError, 'Unreviewed source change'):
            load_quest_module(REF, changed)

    def test_original_gates_and_boss_order(self):
        for script, warp in self.fixture['gate_warps'].items():
            text = self.texts['gmsv/data/npc/'+script]
            self.assertIn('WARP:'+','.join(map(str, warp)), text.splitlines())
            self.assertIn('FREE:LV>79&ENDEV=39&ENDEV=40&ENDEV=42&ENDEV=46', text.splitlines())
            self.assertIn('MONEY:-1', text.splitlines())
        self.assertEqual(self.fixture['gate_warps']['genout/wpm_300_103_228'][0], 300)
        for script, battle in self.fixture['bosses'].items():
            fields = dict(line.split(':',1) for line in self.texts['gmsv/data/npc/'+script].splitlines() if ':' in line)
            self.assertEqual(list(map(int, fields['enemyno'].split(','))), battle['enemies'])
            self.assertEqual([int(fields[k]) for k in ['warpfl','warpx','warpy']], battle['warp'])
            self.assertEqual((fields['dieact'],fields['onebattle']), ('1','0'))

    def test_message_selection_and_closed_rewards(self):
        for script, selected in self.fixture['selected_source_branches'].items():
            # Independent extraction preserves original branch numbers, not
            # current catalog branch positions after the END53 exclusion.
            text = self.texts['gmsv/data/npc/'+script]
            branches = re.findall(r'^EventNo:.*?^EventEnd\s*$', text, re.M|re.S)
            if script.endswith('05'):
                self.assertEqual(selected, list(range(1,8)))
                self.assertIn('EventNo:53', branches[0])
                self.assertIn('GetItem:20570,20571,20572', branches[0])
                for i in selected:
                    self.assertIn('TYPE:MESSAGE', branches[i])
                    self.assertNotRegex(branches[i], r'^(GetItem|DelItem|EndSetFlg|Charm):')
            else:
                item = 2770+int(script[-2:])
                self.assertEqual(selected, [0,1])
                self.assertIn('EVENT:LV>0&ITEM='+str(item), branches[0])
                self.assertNotIn('GetItem:', branches[0])
                self.assertIn('EVENT:LV>0&ITEM!='+str(item), branches[1])
                self.assertIn('GetItem:'+str(item), branches[1])

    def test_source_handoff_does_not_enable_production(self):
        registry = json.loads((ROOT/'client/data/quest-modules.json').read_text())
        self.assertNotIn('transmigration-final', [m['id'] for m in registry['modules']])
        module = load_quest_module(REF, self.spec)
        self.assertEqual(module['npcs'], [])
        self.assertEqual(set(module['items']), {'2771','2772','2773','2774'})
        for item in module['items'].values():
            self.assertEqual(item['raw_columns'][78:82], ['1','1','1','0'])
            self.assertTrue(item['logout_vanish'])

if __name__ == '__main__':
    unittest.main()
