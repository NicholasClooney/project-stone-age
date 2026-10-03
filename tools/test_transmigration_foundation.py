"""Foundation is inert; isolated disabled descriptors coexist with live chains."""
import copy
import hashlib
import re
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from quest_import_common import load_quest_module, registered_quest_modules, merge_quest_module, registry_entries
from quest_source_handlers import npc_enemy, keyword_warp

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'


class FoundationTests(unittest.TestCase):
    def test_public_oracle_includes_pinned_dream_repeat_branches(self):
        # Read original bytes, not importer output, to validate the frozen oracle.
        public=json.loads((ROOT/'client/tests/fixtures/public-quest-npcs.json').read_text())
        extension=public['reviewed_source_extensions']['dream-repeat']
        self.assertEqual(extension['sources'],{
            'gmsv/data/npc/seimu/event/event01_1':'4b79ae2250381e9f9fcfeed398f4fff4ec8b4a0cb0ba020c939fe5910fb26315',
            'gmsv/data/npc/seimu/event/event01_2':'48f2b6db1cfe09371086a51c195f14a49436ba16b0e03b252f3a465de4835577'})
        expected_slots=[450,451,449,549,552,543,653,646,12623,12648,
                        11895,11926,11936,12052,11803,11814,11824,11833,11843,11853]
        self.assertEqual(extension['source_branch_index'],4)
        self.assertEqual(extension['reward_slots'],expected_slots)
        self.assertEqual(len(extension['new_item_ids']),18)
        self.assertEqual(public['reviewed_counts']['catalog_items'],339)
        manifest=json.loads((ROOT/'tools/dream_cave_quest_sources.json').read_text())
        for path,sha in extension['sources'].items():
            raw=(REF/path).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(),sha)
            self.assertEqual(manifest['sources'][path],sha)
            script=path.removeprefix('gmsv/data/npc/')
            blocks=re.findall(r'EventNo:([^\r\n]+)\r?\n(.*?)EventEnd',raw.decode('gb18030'),re.S)
            event,block=blocks[4]
            fields=dict(re.findall(r'^([^:\r\n]+):([^\r\n]*)',block,re.M))
            actions={key:fields[key] for key in ['DelItem','GetItem','GetRandItem'] if key in fields}
            expected=dict(event=int(event),type=fields['TYPE'],condition=fields['EVENT'],
                          actions=actions,enabled=True,events=[32,33,34],source_branch_index=4)
            npcs=[n for n in public['groups']['dream-cave']['npcs'] if n['id'].split('@')[0]==script]
            self.assertEqual(len(npcs),2 if script.endswith('_2') else 1)
            for npc in npcs:
                self.assertEqual([b['source_branch_index'] for b in npc['branches']],manifest['scripts'][script]['branches'])
                self.assertEqual([b for b in npc['branches'] if b['source_branch_index']==4],[expected])
            if script.endswith('_2'):
                self.assertEqual(list(map(int,actions['GetRandItem'].split(','))),expected_slots)
        declared=set()
        for path in ['tools/early_quest_sources.json','tools/brothers_quest_sources.json',
                     'tools/golden_bui_quest_sources.json']+[
                group['manifest'] for name,group in public['groups'].items() if 'manifest' in group]:
            declared.update(json.loads((ROOT/path).read_text())['items'])
        self.assertEqual(public['item_ids'],sorted(declared))

    def test_source_break_and_unkeyed_heading_remain_explicit(self):
        from import_early_quests import parse_script
        text=(REF/'gmsv/data/npc/jaruga/event/ruri05').read_text(encoding='gb18030')
        branch=parse_script(text)[1][0]
        self.assertTrue(branch['source_break'])
        self.assertEqual(branch['actions']['DelItem'],'2700')
        with self.assertRaises(ValueError):parse_script(text.replace('DelItem:2700','DelItem:2700*1'))
        foundation=json.loads((ROOT/'tools/transmigration_foundation_sources.json').read_text())
        wrong=copy.deepcopy(foundation);wrong['reviewed_bindings'][0]['cell'][0]+=1
        with self.assertRaises(ValueError):load_quest_module(REF,wrong)

    def test_real_source_fixture(self):
        fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-foundation.json').read_text())
        self.assertEqual(load_quest_module(REF,fixture['manifest']),fixture['module'])
        guards=[n for n in fixture['module']['npcs'] if n['branches'][0]['type']=='BATTLE']
        self.assertEqual(len(guards),10)
        self.assertTrue(all(len(n['branches'][0]['guard']['enemy_ids'])==10 for n in guards))
        cooldowns=[n for n in guards if n['branches'][0]['guard']['dieact']==0]
        self.assertEqual(len(cooldowns),2)
        self.assertEqual(cooldowns[0]['branches'][0]['guard']['cooldown'],180)

    def test_foundation_has_no_settlement(self):
        modules=list(registered_quest_modules(REF))
        reviewed=json.loads((ROOT/"client/tests/fixtures/public-quest-npcs.json").read_text())["groups"]
        staged=[m for m in modules if m['module_id'].startswith('transmigration-')]
        self.assertEqual({m['module_id'] for m in staged},{'transmigration-'+name for name in ['foundation','earth','fire','wind','water','final']})
        foundation=next(m for m in staged if m['module_id']=='transmigration-foundation')
        self.assertEqual(foundation['enabled_events'],[])
        self.assertEqual(foundation['npcs'],[])
        self.assertEqual(set(map(int,foundation['items'])),{2698,2699,2700,2701,*range(2706,2719),2735,2736,2758,*range(2766,2775)})
        self.assertIn('32021',foundation['staged_world']['map_sources'])
        self.assertNotIn('world',foundation)
        for module in staged:
            group=reviewed[module['module_id']]
            self.assertEqual(module['enabled_events'],group['enabled_events'])
            expected=[n['id'] for n in group['npcs']]
            if module['module_id']=='transmigration-wind':expected.append('sainasu/event/event12@11107:24:6')
            self.assertEqual(sorted(n['id'] for n in module['npcs']),sorted(expected))
        for entry in registry_entries():
            if entry['id'] in ['transmigration-earth','transmigration-fire','transmigration-wind','transmigration-water']:
                self.assertTrue((ROOT/entry['manifest']).is_file())
                self.assertEqual(entry['helper'],'res://server/'+entry['id'].replace('-','_')+'_helper.gd')

    def test_disabled_chain_configuration_is_isolated(self):
        entries=copy.deepcopy(registry_entries())
        names={'transmigration-'+name for name in ['earth','fire','wind','water']}
        for entry in entries:
            if entry['id'] in names:entry['enabled_events']=[]
        with patch('quest_import_common.registry_entries',return_value=entries):
            modules=list(registered_quest_modules(REF))
        self.assertEqual({m['module_id'] for m in modules if m['module_id'] in names},names)
        for module in modules:
            if module['module_id'] in names:self.assertEqual(module['enabled_events'],[])

    def test_npcenemy_rejects_unreviewed_behavior(self):
        source=(REF/'gmsv/data/npc/100/sb_kbu.arg').read_text(encoding='gb18030')
        for bad in [source.replace('onebattle:0','onebattle:1'),source.replace('time:180','time:181'),source+'\nsteal:0']:
            with self.assertRaises(ValueError):npc_enemy(bad,'100/sb_kbu.arg',[41,42])
        with self.assertRaises(ValueError):npc_enemy(source,'other/guard',[41,42])

    def test_all_pinned_gates_and_fail_closed_changes(self):
        gates=json.loads((ROOT/'tools/transmigration_gate_reviews.json').read_text())
        for script,review in gates.items():
            source=(REF/'gmsv/data/npc'/script).read_text(encoding='gb18030')
            branch=keyword_warp(source,script,[39])[1][0]
            self.assertEqual(branch['actions']['Warp'],review['WARP'])
            self.assertEqual(branch['condition'],review['FREE'] or 'LV>0')
            with self.assertRaises(ValueError):keyword_warp(source.replace('WARP:'+review['WARP'],'WARP:1000,1,1'),script,[39])
        paid=keyword_warp((REF/'gmsv/data/npc/genout/wpm_40_13_1').read_text(encoding='gb18030'),'genout/wpm_40_13_1',[46])[1][0]
        self.assertEqual(paid['actions']['DelStone'],'300')
        self.assertIn('%8d',paid['texts']['AcceptMsg'])

    def test_wind_extends_existing_munde_instance_without_reordering(self):
        baseline=load_quest_module(REF,ROOT/'tools/munde_cave_quest_sources.json')
        spec=json.loads((ROOT/'tools/munde_cave_quest_sources.json').read_text())
        spec.update(id='wind-shared-fixture',scripts={'sainasu/event/event12':dict(branches=[1,2,3],events=[41,42])},handlers={},items=[2736])
        spec.pop('missing_condition_items',None)
        wind=load_quest_module(REF,spec)
        merged=merge_quest_module(baseline,wind)
        npc=next(n for n in merged['npcs'] if n.get('source_script')=='sainasu/event/event12')
        self.assertEqual([b['source_branch_index'] for b in npc['branches']],[0,1,2,3])
        self.assertEqual(npc['events'],[9,10,11,12,41,42])
        with self.assertRaises(ValueError):merge_quest_module(merged,wind)
        wrong=copy.deepcopy(wind);wrong['npcs'][0]['cell'][0]+=1
        with self.assertRaises(ValueError):merge_quest_module(baseline,wrong)


if __name__=='__main__':unittest.main()
