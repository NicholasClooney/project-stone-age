"""Read-only oracle: every policy tuple must exist in the pinned source graph."""
import hashlib
import json
from pathlib import Path
import unittest
from import_encounters import build

ROOT = Path('references/chenmingbiao-stone-age/gmsv/data')
POLICY = Path('client/data/quest-wild-drop-policy.json')

class QuestWildDropPolicyTests(unittest.TestCase):
    def test_source_graph_and_complete_selected_slots(self):
        policy = json.loads(POLICY.read_text())
        for name, sha in policy['sources'].items():
            self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), sha, name)
        catalog = build(ROOT)
        expected = set()
        selected = {2457, 2458, 2459, 2534, 2548, 2700, 2751, 2752, 2766, 2767}
        for area in catalog['areas']:
            for group_ref in area['groups']:
                group = catalog['groups'].get(str(group_ref['id']), {})
                for enemy_ref in group.get('enemies', []):
                    enemy = catalog['enemies'].get(str(enemy_ref['id']), {})
                    for drop in enemy.get('drops', []):
                        if drop['item_id'] in selected:
                            expected.add((area['map_id'], area['id'], group['id'], enemy['id'], drop['item_id'], drop['slot']))
        actual = set()
        for row in policy['rules']:
            key = tuple(row[k] for k in ('map', 'area', 'group', 'enemy', 'item', 'slot'))
            actual.add(key)
            area = next(a for a in catalog['areas'] if a['id'] == row['area'])
            group = catalog['groups'][str(row['group'])]
            enemy = catalog['enemies'][str(row['enemy'])]
            drop = next(d for d in enemy['drops'] if d['slot'] == row['slot'])
            self.assertEqual((area['source_line'], group['source_line'], enemy['source_line']), (row['area_line'], row['group_line'], row['enemy_line']))
            self.assertEqual((drop['item_id'], drop['probability']), (row['item'], row['probability']))
            self.assertEqual((group.get('requires_item', -1), group.get('excludes_item', -1)), (row['requires'], row['excludes']))
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), len(policy['rules']))
        self.assertFalse(any(k[4] in {1249, 1238, 2482, 2483, 2468, 2760, 2761, 2762, 2763} for k in actual))

    def test_stone_roots_and_unverified_1099(self):
        warp = (ROOT / 'map/mapwarp.txt').read_text(encoding='gb18030', errors='replace')
        npc_files = list((ROOT / 'npc').rglob('*'))
        self.assertFalse(any('1099' in p.read_text(encoding='gb18030', errors='replace') for p in npc_files if p.is_file()))
        self.assertFalse(any('1099' in line.split(',') for line in warp.splitlines()))
        for name, target in [('wpm_300_247_222', '30301,23,37'), ('wpm_300_182_162', '30307,10,6')]:
            text = (ROOT / 'npc/genout' / name).read_text(encoding='gb18030', errors='replace')
            self.assertIn('LV>64', text); self.assertIn('ENDEV=4', text); self.assertIn(target, text)

if __name__ == '__main__':
    unittest.main()
