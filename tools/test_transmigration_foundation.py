"""First-stage data stays inactive; real source capabilities remain composable."""
import copy
import json
from pathlib import Path
import unittest

from quest_import_common import load_quest_module, registered_quest_modules, merge_quest_module, registry_entries
from quest_source_handlers import npc_enemy, keyword_warp

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'


class FoundationTests(unittest.TestCase):
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

    def test_foundation_has_no_active_chain_or_settlement(self):
        modules=list(registered_quest_modules(REF))
        staged=[m for m in modules if m['module_id'].startswith('transmigration-')]
        self.assertEqual(len(staged),5)
        self.assertTrue(all(not m['enabled_events'] and not m['npcs'] for m in staged))
        foundation=next(m for m in staged if m['module_id']=='transmigration-foundation')
        self.assertEqual(set(map(int,foundation['items'])),{2698,2699,2700,2701,*range(2706,2719),2735,2736,2758,*range(2766,2775)})
        self.assertIn('32021',foundation['staged_world']['map_sources'])
        self.assertNotIn('world',foundation)
        for entry in registry_entries():
            if entry['id'] in ['transmigration-earth','transmigration-fire','transmigration-wind','transmigration-water']:
                self.assertTrue((ROOT/entry['manifest']).is_file())
                self.assertEqual(entry['helper'],'res://server/'+entry['id'].replace('-','_')+'_helper.gd')

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
