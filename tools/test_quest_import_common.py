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
    def test_dream_guards_allow_only_reviewed_empty_start_msg_spelling(self):
        from quest_source_handlers import npc_enemy
        for number,x in [(1,34),(2,33)]:
            script=f'400/sb_muge{number}.arg'
            source=(REFERENCE/'gmsv/data/npc'/script).read_text(encoding='gb18030')
            branch=npc_enemy(source,script,[34])[1][0]
            self.assertEqual(branch['guard']['enemy_ids'],[1095]*3+[1087,1086]+[1096]*5)
            self.assertEqual(branch['actions']['Warp'],f'41,{x},39')
            self.assertEqual(branch['source_fields']['start msg'],'')
            with self.assertRaises(ValueError):npc_enemy(source.replace('start msg:','start msg:unexpected'),script,[34])
            with self.assertRaises(ValueError):npc_enemy(source,'other/script',[34])

    def test_area_spawn_is_source_random_rectangle_and_collision(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-area-spawn.json').read_text())
        spec=fixture['manifest'];module=common.load_quest_module(REFERENCE,spec)
        self.assertEqual(module,fixture['module'])
        npc=module['npcs'][0];rule=npc['source_spawn']
        self.assertEqual(rule['rect'],[230,180,525,200])
        self.assertEqual(len(rule['walkable']),6216)
        self.assertEqual(rule['walkable'].count('1'),6125)
        self.assertTrue(npc['id'].endswith(':area:525:200'))
        from import_world import read_map
        _,_,width,_,tiles,objects,_=read_map(REFERENCE/spec['world']['map_sources']['100']['path'])
        table={int(c[0]):int(c[3]) for l in (REFERENCE/'gmsv/data/map/mapset.txt').read_text(encoding='gb18030').splitlines() if (c:=l.split()) and c[0].isdigit() and len(c)>3}
        for offset,flag in enumerate(rule['walkable']):
            x,y=230+offset%296,180+offset//296
            obj=table.get(objects[y*width+x],0);tile=table.get(tiles[y*width+x],0)
            self.assertEqual(flag=='1',obj==2 or (obj==1 and tile==1))
        for mutate in [lambda s:s['scripts']['seimu/event/event02_1'].pop('spawn_policy'),
                       lambda s:s['sources'].pop('gmsv/data/map/mapset.txt'),
                       lambda s:s['sources'].pop('gmsv/data/npc/jaruga/event/event.template'),
                       lambda s:s['world']['map_sources']['100'].update(sha256='0'*64)]:
            invalid=copy.deepcopy(spec);mutate(invalid)
            with self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)

    def test_dragon_gate_requires_all_original_jewels_without_consumption(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-dragon-gate.json').read_text())
        self.assertEqual(common.load_quest_module(REFERENCE,fixture['manifest']),fixture['module'])
        branch=fixture['module']['npcs'][0]['branches'][0]
        self.assertEqual(branch['condition'],'ITEM=2457&ITEM=2458&ITEM=2459')
        self.assertEqual(branch['actions'],{'Warp':'20807,13,35'})
        from quest_source_handlers import keyword_warp
        source=(REFERENCE/'gmsv/data/npc/genout/wpm_20807_11_37').read_text(encoding='gb18030')
        for old,new in [('ITEM=2459','ITEM!=2459'),('&ITEM=2459',''),('20807,13,35','20807,13,36'),('MONEY:-1','MONEY:0')]:
            with self.assertRaises(ValueError):keyword_warp(source.replace(old,new),'gate',[17])

    def test_miner_gate_and_condition_only_missing_item(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-miner-gate.json').read_text())
        spec=fixture['manifest']
        self.assertEqual(common.load_quest_module(REFERENCE,spec),fixture['module'])
        gate=fixture['module']['npcs'][0]['branches'][0]
        self.assertEqual(gate['actions'],{'Warp':'31806,34,6','DelItem':'2527*1'})
        self.assertEqual(gate['item_deletion_scope'],'bag')
        self.assertNotIn('2391',fixture['module']['items'])
        for mutate in [lambda s:s.pop('missing_condition_items'),
                       lambda s:s['items'].append(2391),
                       lambda s:s['missing_condition_items'][0].update(branch=1),
                       lambda s:s['missing_condition_items'][0].update(reason=''),
                       lambda s:s.update(item_notes={'2391':'not an item'}),
                       lambda s:s['scripts']['giiru/event/giruev2_1'].update(branches=[4])]:
            invalid=copy.deepcopy(spec);mutate(invalid)
            with self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)
        # Even a source-shaped pinned fixture may never use the exception for actions.
        from unittest.mock import patch
        original=quests.parse_script
        for key in ['GetItem','DelItem','GetRandItem']:
            def with_action(text,selected=None,key=key):
                default,branches=original(text,selected)
                branches[0]['actions'][key]='2391'
                return default,branches
            with patch.object(quests,'parse_script',side_effect=with_action):
                with self.assertRaisesRegex(ValueError,'Unreviewed branch action item'):
                    common.load_quest_module(REFERENCE,spec)
        from quest_source_handlers import keyword_warp
        source=(REFERENCE/'gmsv/data/npc/genout/wpm_31805_22_4').read_text(encoding='gb18030')
        for old,new in [('2527*1','2527*2'),('ITEM=2527','ITEM!=2527'),('MONEY:-1','MONEY:0')]:
            with self.assertRaises(ValueError):keyword_warp(source.replace(old,new),'gate',[27])

    def test_free_warp_gate_is_exact_bound_source(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-free-warp-gate.json').read_text())
        self.assertEqual(common.load_quest_module(REFERENCE,fixture['manifest']),fixture['module'])
        from import_world import read_map
        for info in fixture['maps'].values():
            raw=(REFERENCE/info['source']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(),info['source_sha256'])
            mid,name,width,height,*_=read_map(REFERENCE/info['source'])
            self.assertEqual([mid,name,width,height],[info['map_id'],info['name'],info['width'],info['height']])
        from quest_source_handlers import keyword_warp
        source=(REFERENCE/'gmsv/data/npc/genout/wpm_120_19_15').read_text(encoding='gb18030')
        for old,new in [('MONEY:-1','MONEY:1'),('LV>49','LV>48'),('FREE:LV>49','FREE:ALLFREE')]:
            with self.assertRaises(ValueError):keyword_warp(source.replace(old,new),'gate',[37,38])
        branch=fixture['module']['npcs'][0]['branches'][0]
        self.assertEqual(branch['condition'],'LV>49')
        self.assertEqual(branch['actions'],{'Warp':'122,6,5'})
        self.assertEqual(branch['source_fields']['MONEY'],'-1')

    def test_static_random_drops_are_verified_against_original_slots(self):
        spec=gold_bui_manifest()
        expected=[(1305,2760,100),(1306,2761,500),(1307,2763,500),(1308,2762,100)]
        spec['items'] += [2760,2761,2762,2763]
        spec['drops']=[dict(source='gmsv/data/enemy.txt',enemy_id=enemy,item_id=item,probability=chance,audit='four-jewels source audit') for enemy,item,chance in expected]
        result=common.load_quest_module(REFERENCE,spec)
        self.assertEqual([(d['enemy_id'],d['item_id'],d['probability']) for d in result['drops']],expected)
        self.assertTrue(all(d['source_line'] and d['source_slots'] and d['source_raw_columns'] for d in result['drops']))
        result['enabled_events']=[44]
        merged=common.merge_quest_module(dict(npcs=[],items={},jobs=[],reward_pets={},enabled_events=[],provenance={}),result)
        self.assertTrue(merged['reviewed_drops'][spec['id']]['active'])
        for change in [dict(probability=101),dict(item_id=2761),dict(enemy_id=1309),dict(source_line=1),dict(audit=''),dict(probability=True),dict(extra='unsafe')]:
            invalid=copy.deepcopy(spec);invalid['drops'][0].update(change)
            with self.subTest(change=change),self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)
        invalid=copy.deepcopy(spec);invalid['items'].remove(2760)
        with self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)
        invalid=copy.deepcopy(spec);invalid['sources'].pop('gmsv/data/enemy.txt')
        with self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)
        invalid=copy.deepcopy(spec);invalid['drops'].append(copy.deepcopy(spec['drops'][0]))
        with self.assertRaises(ValueError):common.load_quest_module(REFERENCE,invalid)
        # Source-shaped multi-slot enemy: matching one slot must not activate the other.
        import csv,io
        text=(REFERENCE/'gmsv/data/enemy.txt').read_text(encoding='gb18030')
        rows=list(csv.reader(text.splitlines()))
        row=next(r for r in rows if len(r)>33 and r[3]=='1305')
        row[15]='2761';row[25]='500'
        stream=io.StringIO();csv.writer(stream).writerows(rows)
        with self.assertRaisesRegex(ValueError,'All original drop slots'):
            common.reviewed_static_drops(spec,{'gmsv/data/enemy.txt':stream.getvalue()})

    def test_personal_npc_rules_are_exact_pinned_sources(self):
        fixture_path=Path(__file__).resolve().parents[1]/'client/tests/fixtures/personal-quest-npcs.json'
        fixtures=json.loads(fixture_path.read_text())
        for fixture in fixtures:
            result=common.load_quest_module(REFERENCE,fixture['manifest'])
            self.assertEqual(result,fixture['module'])
        from quest_source_handlers import npc_enemy
        source=(REFERENCE/'gmsv/data/npc/300/sb_bac.arg').read_text(encoding='gb18030')
        for old,new in [('time:300','time:301'),('steal:1','steal:0'),('dieact:0','dieact:3')]:
            with self.subTest(new=new),self.assertRaises(ValueError):
                npc_enemy(source.replace(old,new),'source',[27])
        branch=fixtures[2]['module']['npcs'][0]['branches'][0]
        self.assertEqual(branch['actions']['NpcWarp'],'4000.53.101,2000.44.39,5105.14.3,6000.58.44')

    def test_authorized_saton_supplements_preserve_original_source(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-quest-supplements.json').read_text())
        spec=fixture['manifest']
        result=common.load_quest_module(REFERENCE,spec)
        self.assertEqual(result['npcs'],fixture['npcs'])
        for npc in result['npcs']:
            branch=npc['branches'][0]
            source=(REFERENCE/('gmsv/data/npc/'+npc['source_script'])).read_text(encoding='gb18030')
            _, original=quests.parse_script(source,[0])
            self.assertEqual(branch['source_actions'],original[0]['actions'])
            self.assertEqual(branch['source_texts'],original[0]['texts'])
        reward,clean=[n['branches'][0] for n in result['npcs']]
        self.assertEqual(reward['actions']['EndSetFlg'],'13,14')
        self.assertEqual(clean['actions']['CleanFlg'],'13')
        self.assertIn('14保留',clean['confirmation_text'])
        for changes in [dict(end_flags_add=[15]),dict(branch=1),dict(script='unknown'),dict(approval=''),dict(arbitrary_action='GetStone')]:
            invalid=copy.deepcopy(spec);invalid['supplements'][0].update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):
                common.load_quest_module(REFERENCE,invalid)

    def test_keyword_handlers_use_actual_create_and_exact_source(self):
        fixture=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-keyword-gates.json').read_text())
        spec=fixture['manifest'];result=common.load_quest_module(REFERENCE,spec)
        self.assertEqual(result['npcs'],fixture['npcs'])
        self.assertEqual(len(result['npcs']),4)
        self.assertEqual([n['branches'][0]['keyword'] for n in result['npcs']],
                         ['在卡坦有梦德','红色月亮的光芒','蓝色山脉即力量','白色之风即速度'])
        from quest_source_handlers import keyword_warp
        source=(REFERENCE/'gmsv/data/npc/genout/wpm_100_443_127').read_text(encoding='gb18030')
        for extra in ['DelStone:20','NPCPOINT:1,2,3','FREE:LV>10']:
            with self.assertRaises(ValueError):keyword_warp(source+'\n'+extra,'fixture',[9])
        invalid=copy.deepcopy(spec);invalid['handlers']['unknown']=dict(kind='warpman',events=[9])
        with self.assertRaisesRegex(ValueError,'Missing actual create'):common.load_quest_module(REFERENCE,invalid)

    def test_fixed_guards_keep_bound_templates_enemy_order_and_audit(self):
        fixtures=json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-fixed-guards.json').read_text())
        for fixture in fixtures:
            spec=fixture['manifest'];result=common.load_quest_module(REFERENCE,spec)
            self.assertEqual(result['npcs'],fixture['npcs'])
            if spec['id'] == 'munde-guard-fixture':
                self.assertEqual({(d['enemy_id'],d['item_id'],d['probability']) for d in result['drops']},{(526,2482,10),(527,2483,10)})
                self.assertEqual(len(result['drops']),2)
                result['enabled_events']=[9]
                merged=common.merge_quest_module(quests.catalog(REFERENCE),result)
                self.assertTrue(merged['reviewed_drops'][spec['id']]['active'])
                self.assertEqual(merged['reviewed_drops'][spec['id']]['entries'],result['drops'])
                invalid=copy.deepcopy(spec);invalid['items']=[]
                with self.assertRaisesRegex(ValueError,'guard reward item'):common.load_quest_module(REFERENCE,invalid)
            for npc in result['npcs']:
                branch=npc['branches'][0]
                self.assertEqual(branch['guard']['enemy_ids'],list(map(int,branch['actions']['Battle'].split(','))))
                for enemy in branch['combat_audit']['enemies'].values():
                    self.assertEqual(enemy['tactics'],enemy['raw_columns'][1])
                for base in branch['combat_audit']['bases'].values():
                    self.assertEqual(len(base['skills']),7)
                    self.assertEqual([s['raw'] for s in base['skills']],base['raw_columns'][25:32])
            invalid=copy.deepcopy(spec)
            invalid['sources']={k:v for k,v in invalid['sources'].items() if not k.endswith('.template')}
            with self.assertRaisesRegex(ValueError,'template binding'):common.load_quest_module(REFERENCE,invalid)
        from quest_source_handlers import npc_enemy
        raw=(REFERENCE/'gmsv/data/npc/100/sb_go.arg').read_text(encoding='gb18030')
        for altered in [raw.replace('dieact:1','dieact:0'),raw+'\nsteal:1',raw.replace('enemyno:527,526,528,529','enemyno:527,bad')]:
            with self.assertRaises(ValueError):npc_enemy(altered,'fixture',[9])

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
        for invalid in ['-1000', 'LV*30', 'LV*20+1', 'lv*20', '2147483648', '999999999999999999999999', 'bad']:
            with self.assertRaisesRegex(ValueError, 'Unsupported DelStone'):
                quests.parse_script('EventNo:-1\nTYPE:REQUEST\nEVENT:LV>0\nDelStone:'+invalid+'\nEventEnd')

    def test_level_fees_source_fixture(self):
        fixture = json.loads((Path(__file__).resolve().parents[1]/'client/tests/fixtures/original-level-fees.json').read_text())
        for relative, digest in fixture['provenance']['sources'].items():
            self.assertEqual(hashlib.sha256((REFERENCE/relative).read_bytes()).hexdigest(), digest)
        for npc in fixture['npcs']:
            raw = (REFERENCE/('gmsv/data/npc/'+npc['source_script'])).read_text(encoding='gb18030')
            _, branches = quests.parse_script(raw, [b['source_branch_index'] for b in npc['branches']])
            self.assertEqual([b['actions'] for b in branches], [b['actions'] for b in npc['branches']])
        self.assertTrue(quests.valid_stone_cost('LV*20'))
        self.assertTrue(quests.valid_stone_cost('LV*40'))
        self.assertTrue(quests.valid_stone_cost('2147483647'))

    def test_service_builder_and_public_private_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            registry = root/'modules.json'
            registry.write_text(json.dumps({'version': 1, 'modules': [
                {'id': 'golden-bui', 'builder': 'golden-bui', 'enabled_events': [44]}]}))
            result = common.extend_registered_modules(REFERENCE, quests.catalog(REFERENCE), registry)
            quests.write_quest_catalogs(root, result)
            public = json.loads((root/'quests/catalog.json').read_text())
            private = json.loads((root/'server/golden-bui.json').read_text())
            self.assertNotIn('server_catalogs', public)
            self.assertNotIn('services', public)
            self.assertNotIn('questions', json.dumps(public))
            self.assertEqual(len(private['services']), 70)
            for npc in public['npcs']:
                if 'kind' in npc:
                    self.assertIn(npc['service_id'], private['services'])
            fixture_root = Path(__file__).resolve().parents[1]/'client/tests/fixtures'
            for npc in json.loads((fixture_root/'golden-bui-public-npcs.json').read_text()):
                self.assertIn(npc, public['npcs'])
            fixture = json.loads((fixture_root/'golden-bui-private-services.json').read_text())
            for key, rule in fixture['services'].items():
                expected = copy.deepcopy(private['services'][key])
                if 'questions' in expected: expected['questions'] = expected['questions'][:2]
                self.assertEqual(rule, expected)
            registry.write_text(json.dumps({'version': 1, 'modules': [
                {'id': 'golden-bui', 'builder': 'arbitrary-module', 'enabled_events': [44]}]}))
            with self.assertRaisesRegex(ValueError, 'Unreviewed quest builder'):
                list(common.registered_quest_modules(REFERENCE, registry))

    def test_private_service_catalog_remains_in_web_core(self):
        from unittest.mock import patch
        import plan_web_packs
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, data in [('world/manifest.json', {'maps': {}}),
                               ('characters/catalog.json', {}), ('battle/manifest.json', {}),
                               ('server/golden-bui.json', {'services': {}})]:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(data))
            with patch.object(plan_web_packs, 'LEGACY', root):
                self.assertIn(plan_web_packs.RES+'server/golden-bui.json', plan_web_packs.plan()['packs']['core'])

    def test_portable_npc_image_identity(self):
        ids = ['a/b', 'a-b', 'a:b', 'a_b', 'A/b', 'a%2Fb', '原人物@810:1:2',
               'quiz/equiz_02@810:20:29', 'quiz/equiz_02@850:20:29']
        paths = [quests.quest_npc_image_path(ident) for ident in ids]
        self.assertEqual(len(set(path.casefold() for path in paths)), len(ids))
        for ident, path in zip(ids, paths):
            filename = Path(path).name
            self.assertRegex(filename, r'^n-[0-9a-f]+\.png$')
            self.assertEqual(bytes.fromhex(filename[2:-4]).decode('utf-8'), ident)
            self.assertLessEqual(len(filename), 246)
        for invalid in ['', 'x'*121]:
            with self.assertRaises(ValueError): quests.quest_npc_image_path(invalid)

    def test_portable_paths_remain_in_catalog_and_map_packs(self):
        from unittest.mock import patch
        import plan_web_packs
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            maps = {}
            npcs = []
            for map_id in (810, 850):
                ident = f'quiz/equiz_02@{map_id}:20:29'
                path = quests.quest_npc_image_path(ident)
                target = root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'fixture')
                maps[str(map_id)] = {'path': f'world/{map_id}.json'}
                npcs.append({'id': ident, 'map_id': map_id, 'path': path})
            for name, data in [('world/manifest.json', {'maps': maps}),
                               ('world/810.json', {'images': {}}), ('world/850.json', {'images': {}}),
                               ('characters/catalog.json', {}), ('battle/manifest.json', {})]:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(data))
            quests.write_quest_catalogs(root, {'npcs': npcs})
            self.assertEqual(json.loads((root/'quests/catalog.json').read_text())['npcs'], npcs)
            with patch.object(plan_web_packs, 'LEGACY', root):
                plan = plan_web_packs.plan()
                for npc in npcs:
                    self.assertIn(plan_web_packs.RES+npc['path'], plan['packs'][f'map-{npc["map_id"]}'])

    def test_module_world_choices_and_audited_drops(self):
        import import_golden_bui
        import import_world
        module = import_golden_bui.build(REFERENCE)
        portals = import_world.read_portals(REFERENCE/'gmsv/data/npc/genout')
        selected = common.apply_module_portal_choices(portals, [module['world']])
        for cell in ([28, 27], [29, 27]):
            exits = [p for p in selected if p['from_map'] == 810 and p['cell'] == cell]
            self.assertEqual([p['to_map'] for p in exits], [809])
        self.assertEqual(len(module['world']['map_sources']), 37)
        self.assertIn('831', module['world']['map_sources'])
        forged = copy.deepcopy(module['world'])
        forged['portal_choices'][0]['to_map'] = 999999
        with self.assertRaisesRegex(ValueError, 'not present in source'):
            common.apply_module_portal_choices(portals, [forged])
        module['enabled_events'] = [44]
        merged = common.merge_quest_module(quests.catalog(REFERENCE), module)
        audit = merged['reviewed_drops']['golden-bui']
        self.assertTrue(audit['active'])
        self.assertEqual(len(audit['entries']), 18)
        for entry in audit['entries']:
            self.assertEqual(entry['probability'], 600)
            self.assertEqual(entry['item_id'], 2752 if entry['enemy_id'] % 2 else 2751)
        module['enabled_events'] = []
        self.assertFalse(common.merge_quest_module(quests.catalog(REFERENCE), module)['reviewed_drops']['golden-bui']['active'])

    def test_empty_registry_does_not_activate_fixture(self):
        base = quests.catalog(REFERENCE)
        with tempfile.TemporaryDirectory() as folder:
            registry = Path(folder)/'modules.json'
            registry.write_text(json.dumps({'version': 1, 'modules': []}))
            self.assertEqual(common.extend_registered_modules(REFERENCE, base, registry), base)


if __name__ == '__main__':
    unittest.main()
