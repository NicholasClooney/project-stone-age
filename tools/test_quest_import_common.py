"""Real-source module boundaries: pre-parse exclusion and create identity."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import tempfile

import import_early_quests as quests
import quest_import_common as common

REFERENCE = Path(__file__).resolve().parents[1] / 'references/chenmingbiao-stone-age'


def gold_bui_manifest():
    paths = ['gmsv/data/npc/quiz/quiz.create', 'gmsv/data/npc/quiz/equiz_01',
             'gmsv/data/npc/quiz/equiz_02', 'gmsv/data/itemset.txt',
             'gmsv/data/jobdaily.txt', 'gmsv/data/enemy.txt', 'gmsv/data/enemybase.txt']
    return dict(version=1, id='gold-bui-fixture', reference_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',
                sources={p: hashlib.sha256((REFERENCE/p).read_bytes()).hexdigest() for p in paths},
                creates=['gmsv/data/npc/quiz/quiz.create'],
                scripts={'quiz/equiz_01': dict(branches=[3], events=[44]),
                         'quiz/equiz_02': dict(branches=[4], events=[44])},
                items=[2753], reward_enemies=[14], jobs=[])


class QuestModuleTests(unittest.TestCase):
    def test_excluded_unsupported_language_never_reaches_parser(self):
        source = (REFERENCE/'gmsv/data/npc/quiz/equiz_02').read_text(encoding='gb18030')
        unsupported = source.replace('PET=77-12', 'PET=77-12EV')
        with self.assertRaisesRegex(ValueError, 'Unsupported predicate'):
            quests.parse_script(unsupported)
        self.assertEqual(quests.parse_script(unsupported, [4]), quests.parse_script(source, [4]))
        _, branches = quests.parse_script(source, [4])
        self.assertEqual(len(branches), 1)
        self.assertEqual(branches[0]['source_line'], 38)
        self.assertEqual(branches[0]['source_branch_index'], 4)
        self.assertEqual(branches[0]['actions'], {'GetPet': '14', 'DelItem': '2753', 'EndSetFlg': '44'})
        for indices in [[9], [-1], [4, 4], [4, 3], [True], []]:
            with self.subTest(indices=indices), self.assertRaises(ValueError):
                quests.parse_script(source, indices)

    def test_actual_multi_map_instances_and_reward(self):
        data = common.load_quest_module(REFERENCE, gold_bui_manifest())
        self.assertEqual([n['id'] for n in data['npcs']], [
            'quiz/equiz_01@810:29:16', 'quiz/equiz_02@810:28:16',
            'quiz/equiz_01@850:29:16', 'quiz/equiz_02@850:28:16'])
        self.assertEqual(data['reward_pets']['14']['template_id'], 12)
        self.assertTrue(all(b['event'] == 44 for n in data['npcs'] for b in n['branches']))
        self.assertTrue(all(n['source_create'] == 'gmsv/data/npc/quiz/quiz.create' for n in data['npcs']))
        self.assertTrue(all(b['enabled'] and b['events'] == [44] for n in data['npcs'] for b in n['branches']))

    def test_missing_binding_instance_item_and_hash_rejected(self):
        base = gold_bui_manifest()
        variants = []
        spec = copy.deepcopy(base); spec['scripts']['quiz/old-copy'] = spec['scripts'].pop('quiz/equiz_02'); variants.append(spec)
        spec = copy.deepcopy(base); spec['scripts']['quiz/equiz_02']['instances'] = ['quiz/equiz_02@999:1:1']; variants.append(spec)
        spec = copy.deepcopy(base); spec['items'] = []; variants.append(spec)
        spec = copy.deepcopy(base); spec['sources']['gmsv/data/npc/quiz/equiz_02'] = '0'*64; variants.append(spec)
        for spec in variants:
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                common.load_quest_module(REFERENCE, spec)

    def test_merge_atomic_and_preserves_existing_ids(self):
        base = quests.catalog(REFERENCE)
        before = copy.deepcopy(base)
        data = common.load_quest_module(REFERENCE, gold_bui_manifest())
        merged = common.merge_quest_module(base, data)
        self.assertEqual(base, before)
        self.assertEqual(merged['npcs'][:len(base['npcs'])], base['npcs'])
        self.assertIn('gold-bui-fixture', merged['provenance']['modules'])
        with self.assertRaisesRegex(ValueError, 'Duplicate quest instance'):
            common.merge_quest_module(merged, data)
        collision = copy.deepcopy(data)
        collision['items']['2414'] = {'raw_columns': ['wrong']}
        with self.assertRaisesRegex(ValueError, 'Conflicting quest definition'):
            common.merge_quest_module(base, collision)
        self.assertEqual(base, before)

    def test_shared_items_keep_existing_annotations(self):
        base = quests.catalog(REFERENCE)
        data = common.load_quest_module(REFERENCE, gold_bui_manifest())
        data['items']['2414'] = copy.deepcopy(base['items']['2414'])
        data['items']['2414']['description'] = 'module should not overwrite existing note'
        merged = common.merge_quest_module(base, data)
        self.assertEqual(merged['items']['2414'], base['items']['2414'])

    def test_transaction_fixture_is_exact_selected_source(self):
        fixture = json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/bonus-quest-transactions.json').read_text())
        for relative, digest in fixture['provenance']['sources'].items():
            self.assertEqual(hashlib.sha256((REFERENCE/relative).read_bytes()).hexdigest(), digest)
        for npc in fixture['npcs']:
            raw = (REFERENCE/('gmsv/data/npc/'+npc['source_script'])).read_text(encoding='gb18030')
            indices = [b['source_branch_index'] for b in npc['branches']]
            _, branches = quests.parse_script(raw, indices)
            self.assertEqual([b['actions'] for b in branches], [b['actions'] for b in npc['branches']])
            self.assertEqual([b['condition'] for b in branches], [b['condition'] for b in npc['branches']])
        for invalid in ['PET=25-223*2', 'PET<25-223*1', 'EVDEL']:
            with self.assertRaisesRegex(ValueError, 'Unsupported DelPet'):
                quests.parse_script('EventNo:35\nTYPE:ACCEPT\nEVENT:LV>0\nDelPet:'+invalid+'\nEventEnd')
        for invalid in ['-1000', 'LV*20', 'bad']:
            with self.assertRaisesRegex(ValueError, 'Unsupported DelStone'):
                quests.parse_script('EventNo:-1\nTYPE:REQUEST\nEVENT:LV>0\nDelStone:'+invalid+'\nEventEnd')

    def test_empty_registry_does_not_activate_fixture(self):
        base = quests.catalog(REFERENCE)
        with tempfile.TemporaryDirectory() as folder:
            registry = Path(folder)/'modules.json'
            registry.write_text(json.dumps({'version': 1, 'modules': []}))
            self.assertEqual(common.extend_registered_modules(REFERENCE, base, registry), base)


if __name__ == '__main__':
    unittest.main()
