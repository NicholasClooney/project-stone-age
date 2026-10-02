import json
import unittest
from pathlib import Path
from import_early_quests import catalog, parse_script
from import_brothers_quests import extend, SPEC, MAPS

class BrothersSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=extend('references/chenmingbiao-stone-age',catalog('references/chenmingbiao-stone-age'),parse_script)
        cls.npcs={n['id']:n for n in cls.data['npcs']}
    def test_live_binding_and_out_of_scope(self):
        self.assertNotIn('giiru/event/event30_5', self.npcs)
        kuy=self.npcs['king/event69_1']
        self.assertEqual((kuy['map_id'],kuy['cell']),(30600,[15,10]))
        self.assertEqual(len(kuy['branches']),5)
        self.assertFalse(any('69' in b['condition'] or '19621' in str(b['actions']) for b in kuy['branches']))
        self.assertEqual(kuy['branches'][0]['actions'],{'DelItem':'2547','GetPet':'355','EndSetFlg':'54'})
        self.assertEqual(kuy['branches'][1]['actions'],{'DelItem':'2532','EndSetFlg':'54'})
    def test_no_fabricated_interlock(self):
        for key in ['king/event69_1']+['giiru/event/event30_'+str(i) for i in [1,2,3,4,6]]:
            for branch in self.npcs[key]['branches']:
                self.assertNotIn('EV=28',branch['condition'])
                self.assertNotIn('EV=31',branch['condition'])
        self.assertEqual([self.npcs['giiru/event/ev28_ed'+str(i)]['branches'][0]['actions']['GetPet'] for i in range(1,6)],['54','57','55','56','481'])
    def test_original_maze_and_typo(self):
        correct=self.npcs['genout/wpm_31910_8_9']['branches'][0]
        self.assertEqual(correct['actions'],{'Warp':'31911,6,15','DelItem':'2548*1'})
        self.assertNotIn('DelItem',self.npcs['giiru/event/ev28_23']['branches'][0]['actions'])
        self.assertEqual(self.npcs['300/sb_5b5.arg']['branches'][0]['actions'],{'Battle':'1015','Warp':'31706,15,16'})
    def test_imported_original_gates(self):
        manifest=json.loads(Path('client/assets/legacy/world/manifest.json').read_text())
        portals=manifest['portals']
        self.assertTrue(any(p['from_map']==300 and p['cell']==[343,191] and p['to_map']==31701 and not p.get('disabled') for p in portals))
        scripts=json.loads(SPEC.read_text())['scripts']
        self.assertFalse(any(p.get('gate_source') in scripts for p in portals))
        self.assertTrue(set(map(str,MAPS)) <= set(manifest['maps']))
    def test_web_pack_ownership_and_runtime_sheet(self):
        import plan_web_packs as packs
        plan=packs.plan()
        owners={path:name for name,paths in plan['packs'].items() for path in paths}
        core=plan['packs']['core']
        self.assertIn(packs.RES+'quests/catalog.json',core)
        self.assertIn(packs.RES+'encounters/catalog.json',core)
        imported=json.loads((packs.LEGACY/'quests/catalog.json').read_text())
        for npc in imported['npcs']:
            if not any(e in [28,29,30,31,54] for e in npc['events']):continue
            self.assertIn(owners[packs.RES+npc['path']], ['core']+plan['maps'][str(npc['map_id'])])
        for item in imported['items'].values():
            self.assertEqual(owners[packs.RES+item['icon_path']],'core')
        runtime=json.loads((packs.LEGACY/'battle/sprites/100461.json').read_text())
        self.assertTrue(runtime['bitmaps'])
        for file in runtime['files']:
            self.assertEqual(owners[packs.RES+'battle/'+file],'sprite-100461')
        self.assertNotIn(packs.RES+'battle/manifest.json',owners)
        all_files=[p for paths in plan['packs'].values() for p in paths]
        self.assertEqual(len(all_files),len(set(all_files)))
    def test_temporary_items_and_visible_limits(self):
        for i in range(2507,2518):self.assertTrue(self.data['items'][str(i)]['logout_vanish'])
        for i in [2532,2547,2548,2549]:self.assertFalse(self.data['items'][str(i)]['logout_vanish'])
        self.assertIn('不发黄金羚羊',self.data['items']['2532']['description'])
        self.assertIn('尚未实现',self.data['items']['2551']['description'])
        self.assertEqual(set(map(int,json.loads(SPEC.read_text())['map_sources'])),set(MAPS))
if __name__=='__main__':unittest.main()
