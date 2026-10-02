import json
import tempfile
import unittest
from pathlib import Path
from import_encounters import ALBUM_PETS, RARE, add_album_pets, add_rare_encounters, atoi, build, choices, drop_slots, wait_only

ROOT = Path('references/chenmingbiao-stone-age/gmsv/data')

class EncounterImportTests(unittest.TestCase):
    def test_c_integer_parser(self):
        self.assertEqual(atoi('4.50'), 4)
        self.assertEqual(atoi(' -2tail'), -2)
        self.assertEqual(atoi(''), 0)

    def test_weighted_slots_preserve_original_ids(self):
        self.assertEqual(choices(['7','8']+['']*8+['1','0']+['']*8,0,10), [{'id':7,'weight':1},{'id':8,'weight':0}])

    def test_drop_slots_are_aligned_and_blank_probabilities_are_zero(self):
        row = [''] * 34
        row[14], row[24] = '2468', '700'
        row[15] = '17'
        row[23], row[33] = '18', '999'
        self.assertEqual(drop_slots(row), [dict(slot=0,item_id=2468,probability=700,denominator=1000),
            dict(slot=1,item_id=17,probability=0,denominator=1000),
            dict(slot=9,item_id=18,probability=999,denominator=1000)])
        self.assertEqual(drop_slots([''] * 14), [])

    def test_wait_only_is_a_conservative_source_subset(self):
        tactic = 'at:0;1;1|gu:0|es:0|wa:1;0;0;0;0;0;0;'
        self.assertTrue(wait_only(tactic))
        for other in [tactic.replace('at:0;', 'at:1;'), tactic.replace('gu:0', 'gu:1'),
                      tactic.replace('es:0', 'es:1'), tactic.replace('wa:1;', 'wa:0;'), '']:
            self.assertFalse(wait_only(other))

    @unittest.skipUnless(ROOT.exists(), 'local reference required')
    def test_reference_links_and_source_fields(self):
        data=build(ROOT)
        area=next(a for a in data['areas'] if a['id']==21)
        self.assertEqual(area['rect'], [582,399,783,560])
        self.assertEqual(area['groups'][0], {'id':88,'weight':50})
        self.assertEqual(data['groups']['88']['enemies'], [{'id':119,'weight':1}])
        self.assertEqual(data['templates']['1']['sprite'],100250)
        self.assertEqual(data['templates']['1']['wild_growth'],4)
        self.assertEqual(data['templates']['1']['raw_growth'],'4.50')
        # enemybase column 13 E_T_MODAI: 乌力 150, 乌力乌力 100 (charm-and-loyalty.md).
        self.assertEqual(data['templates']['1']['modai'],150)
        self.assertEqual(data['templates']['2']['modai'],100)
        self.assertEqual(data['enemies']['119']['level_min'],1)
        self.assertEqual(data['enemies']['119']['level_max'],1)
        self.assertGreater(len(data['areas']),600)
        self.assertEqual(len(data['provenance']['tables']),4)
        self.assertTrue(next(a for a in data['areas'] if a['id']==41)['invalid_weights'])
        self.assertTrue(data['groups']['125']['invalid_weights'])
        self.assertTrue(data['groups']['141']['invalid_weights'])
        self.assertFalse(data['groups']['88']['invalid_weights'])

    @unittest.skipUnless(ROOT.exists(), 'local reference required')
    def test_wood_original_drop_columns_and_wait_tactics(self):
        data = build(ROOT)
        enemy = data['enemies']['563']
        self.assertEqual(enemy['drops'], [dict(slot=0, item_id=2468, probability=700, denominator=1000)])
        self.assertTrue(enemy['wait_only'])
        self.assertEqual(enemy['experience'], 0)
        self.assertEqual(enemy['pet_flag'], 0)
        self.assertEqual(data['groups']['414']['requires_item'], 2478)
        self.assertEqual(data['groups']['414']['excludes_item'], -1)
        area = next(a for a in data['areas'] if a['id'] == 267)
        self.assertEqual(area['map_id'], 1099)
        self.assertEqual(area['groups'], [dict(id=414, weight=1)])

    def test_album_pets_are_stat_less_templates_that_never_spawn(self):
        data={'templates':{'1':{'id':1,'name':'乌力','sprite':100250}},'provenance':{}}
        with tempfile.TemporaryDirectory() as folder:
            pets=Path(folder)/'pets.json';album=Path(folder)/'petName.h'
            pets.write_text(json.dumps({'pets':[{'album':417,'name':'巴雅','face':28542,'sprite':101869}]},ensure_ascii=False))
            album.write_text('{ 0,\t"乌力" /*"x"*/,\t28001\t},\n//{ 417, "旧名", 1},\n{ 417,    "巴雅",    28542}, //\n',encoding='utf-8')
            add_album_pets(data,pets,album)
            self.assertEqual(data['templates']['10417'],{'id':10417,'name':'巴雅','sprite':101869,'pet_flag':1,'source':'8.0','stats_known':False,'album':417,'face':28542})
            self.assertEqual(data['provenance']['album_pets']['count'],1)
            album.write_text('{ 417, "别的", 28542},\n',encoding='utf-8')
            with self.assertRaises(ValueError):add_album_pets({'templates':{},'provenance':{}},pets,album)
            with self.assertRaises(ValueError):add_album_pets({'templates':{'9':{'name':'巴雅'}},'provenance':{}},pets,Path(folder)/'missing.h')

    @unittest.skipUnless(ROOT.exists(), 'local reference required')
    def test_classic_riding_lv1_rows_preserve_source_templates(self):
        original = build(ROOT)
        data = build(ROOT)
        add_rare_encounters(data)
        additions = [(809, 1642, 90211, 91111, 100, 38, 131),
                     (1110, 2138, 2138, 91112, 500, 639, 119),
                     (1095, 2119, 2119, 91113, 500, 638, 96)]
        self.assertEqual(data['templates'], original['templates'])
        self.assertEqual(data['enemies']['1642'], original['enemies']['1642'])
        self.assertEqual(data['enemies']['1642']['pet_flag'], 0)
        self.assertEqual(data['enemies']['90211']['clone_of'], 1642)
        for tid, source, enemy, group, map_id, area_id, total in additions:
            row = original['enemies'][str(source)]
            self.assertEqual((row['template_id'], row['level_min'], row['level_max']), (tid, 1, 1))
            self.assertEqual(original['templates'][str(tid)]['pet_flag'], 1)
            self.assertEqual(data['enemies'][str(enemy)]['pet_flag'], 1)
            for key in ['tactics', 'condition', 'experience', 'drops']:
                self.assertEqual(data['enemies'][str(enemy)][key], row[key])
            added = data['groups'][str(group)]
            self.assertEqual(added['enemies'], [dict(id=enemy, weight=1)])
            self.assertEqual(added['rare']['origin'], 'added')
            area = next(a for a in data['areas'] if (a['map_id'], a['id']) == (map_id, area_id))
            self.assertIn(dict(id=group, weight=1), area['groups'])
            ordinary = sum(g['weight'] for g in area['groups'] if str(g['id']) in data['groups']
                           and data['groups'][str(g['id'])]['requires_item'] < 0
                           and data['groups'][str(g['id'])]['excludes_item'] < 0)
            self.assertEqual(ordinary, total)
            self.assertTrue(0.005 < 1 / ordinary < 0.015)

    def rare_fixture(self):
        area = dict(id=5, map_id=9, groups=[dict(id=1, weight=3), dict(id=2, weight=1)])
        other = dict(id=5, map_id=8, groups=[])
        return dict(areas=[area, other], provenance={},
            groups={'1': dict(id=1, requires_item=-1, excludes_item=-1, enemies=[dict(id=10, weight=1)]),
                    '2': dict(id=2, requires_item=7, excludes_item=-1, enemies=[dict(id=11, weight=1)])},
            enemies={'10': dict(id=10, template_id=100, level_min=90, level_max=95, max_count=5, min_count=1, pet_flag=1),
                     '11': dict(id=11, template_id=100, level_min=90, level_max=95, max_count=5, min_count=1, pet_flag=1),
                     '12': dict(id=12, template_id=101, level_min=1, level_max=1, max_count=3, min_count=1, pet_flag=1),
                     '13': dict(id=13, template_id=102, level_min=1, level_max=1, max_count=1, min_count=1, pet_flag=0)},
            templates={'100': dict(id=100, name='高'), '101': dict(id=101, name='稀'), '102': dict(id=102, name='克')})

    def write_rare(self, folder, **spec):
        path = Path(folder)/'rare.json'
        path.write_text(json.dumps(dict(dict(areas=[], clones=[], encounters=[]), **spec), ensure_ascii=False))
        return path

    def test_rare_encounters_add_a_marked_lv1_group(self):
        data = self.rare_fixture()
        entry = dict(group_id=900, template_id=101, name='稀', enemy_id=12, companion_id=10, map_id=9, area_id=5, weight=1, origin='added', reason='r')
        clone = dict(group_id=901, template_id=102, name='克', enemy_id=50, companion_id=None, map_id=9, area_id=5, weight=1, origin='original_area', reason='r')
        with tempfile.TemporaryDirectory() as folder:
            add_rare_encounters(data, self.write_rare(folder, areas=[dict(map_id=9, area_id=5, scale=4)],
                clones=[dict(id=50, template_id=102, reason='r', **{'from': 13})], encounters=[entry, clone]))
        area = data['areas'][0]
        self.assertEqual(area['groups'], [dict(id=1, weight=12), dict(id=2, weight=4), dict(id=900, weight=1), dict(id=901, weight=1)])
        self.assertEqual(area['weight_scale'], 4)
        self.assertEqual(data['areas'][1]['groups'], [])
        self.assertEqual(data['groups']['900']['enemies'], [dict(id=12, weight=1), dict(id=10, weight=1)])
        self.assertEqual(data['groups']['900']['rare']['origin'], 'added')
        self.assertEqual(data['groups']['901']['enemies'], [dict(id=50, weight=1)])
        self.assertEqual({k: data['enemies']['50'][k] for k in ['template_id', 'level_min', 'level_max', 'max_count', 'pet_flag', 'clone_of']},
                         dict(template_id=102, level_min=1, level_max=1, max_count=1, pet_flag=1, clone_of=13))
        self.assertEqual(data['enemies']['13']['pet_flag'], 0)
        self.assertEqual(data['provenance']['rare_encounters']['encounters'], 2)

    def test_rare_encounters_add_an_alone_lv1_group(self):
        data = self.rare_fixture()
        entry = dict(group_id=900, alone_group_id=950, template_id=101, name='稀', enemy_id=12, companion_id=10, map_id=9, area_id=5, weight=1, origin='original_area', reason='r')
        with tempfile.TemporaryDirectory() as folder:
            add_rare_encounters(data, self.write_rare(folder, encounters=[entry]))
        self.assertEqual(data['areas'][0]['groups'][-2:], [dict(id=900, weight=1), dict(id=950, weight=1)])
        self.assertEqual(data['groups']['900']['enemies'], [dict(id=12, weight=1), dict(id=10, weight=1)])
        self.assertEqual(data['groups']['950']['enemies'], [dict(id=12, weight=1)])
        rare = data['groups']['950']['rare']
        self.assertEqual((rare['origin'], rare['enemy_id'], rare['template_id'], rare['alone']), ('original_area', 12, 101, True))
        self.assertNotIn('alone', data['groups']['900']['rare'])
        self.assertEqual(data['provenance']['rare_encounters']['alone'], 1)
        with tempfile.TemporaryDirectory() as folder:
            for row in [dict(entry, alone_group_id=1), dict(entry, companion_id=None)]:
                with self.assertRaises(ValueError, msg=row):
                    add_rare_encounters(self.rare_fixture(), self.write_rare(folder, encounters=[row]))

    def test_rare_encounters_refuse_bad_rows(self):
        entry = dict(group_id=900, template_id=101, name='稀', enemy_id=12, companion_id=10, map_id=9, area_id=5, weight=1, origin='added', reason='r')
        bad = [dict(entry, enemy_id=10, template_id=100, name='高'),  # not Lv1
               dict(entry, enemy_id=13, template_id=102, name='克'),  # not capturable
               dict(entry, name='别的'),                              # name does not match
               dict(entry, companion_id=11),                          # companion only in a gated group
               dict(entry, group_id=1),                               # group id taken
               dict(entry, origin='original')]
        with tempfile.TemporaryDirectory() as folder:
            for row in bad:
                with self.assertRaises(ValueError, msg=row):
                    add_rare_encounters(self.rare_fixture(), self.write_rare(folder, encounters=[row]))
            with self.assertRaises(ValueError):
                add_rare_encounters(self.rare_fixture(), self.write_rare(folder, areas=[dict(map_id=7, area_id=5, scale=2)], encounters=[entry]))

    def test_shipped_rare_encounters_are_level_one_near_one_percent(self):
        spec = json.loads(RARE.read_text())
        ids = [e['group_id'] for e in spec['encounters']]+[e['alone_group_id'] for e in spec['encounters'] if 'alone_group_id' in e]
        self.assertEqual(len(set(ids)), len(ids))
        # Every pet hunted at Lv1 has a group with no other enemy.
        self.assertTrue(all(('alone_group_id' in e) == (e['companion_id'] is not None) for e in spec['encounters']))
        self.assertTrue(all(e['weight'] == 1 and e['origin'] in ('original_area', 'added') and e['reason'] for e in spec['encounters']))
        if not ROOT.exists():
            return
        data = add_rare_encounters(build(ROOT), RARE)
        for item in spec['encounters']:
            area = next(a for a in data['areas'] if a['map_id'] == item['map_id'] and a['id'] == item['area_id'])
            total = sum(c['weight'] for c in area['groups'] if str(c['id']) in data['groups']
                        and data['groups'][str(c['id'])]['requires_item'] < 0 and data['groups'][str(c['id'])]['excludes_item'] < 0)
            self.assertTrue(0.005 <= 1/total <= 0.015, f"{item['name']}: 1/{total}")

    def test_shipped_album_pets_have_unique_albums_and_sprites(self):
        pets=json.loads(ALBUM_PETS.read_text())['pets']
        self.assertEqual(len({p['album'] for p in pets}),len(pets))
        self.assertEqual(len({p['sprite'] for p in pets}),len(pets))
        self.assertTrue(all(100000<p['sprite']<110000 and 28000<p['face']<29000 for p in pets))

    @unittest.skipUnless(ROOT.exists(), 'local reference required')
    def test_family_completion_preserves_sources_and_capture_parameters(self):
        original = build(ROOT)
        data = add_rare_encounters(build(ROOT), RARE)
        placements = {803:(1636,32006,616),804:(1637,32007,617),
                      805:(1638,32008,618),806:(1639,32010,620),
                      725:(1558,100,56),726:(1559,100,56),727:(1560,100,56),
                      779:(1612,200,152),754:(1588,300,311),
                      755:(1660,300,311),756:(1589,300,311)}
        spec = json.loads(RARE.read_text())
        classic = json.loads(Path('client/data/classic-pets.json').read_text())['pets']
        for tid, (source, mid, aid) in placements.items():
            rows = [e for e in spec['encounters'] if e['template_id'] == tid]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual((row['map_id'], row['area_id']), (mid, aid))
            self.assertIsNone(row['companion_id'])
            self.assertNotIn('alone_group_id', row)
            self.assertEqual(data['enemies'][str(source)], original['enemies'][str(source)])
            self.assertEqual(data['templates'][str(tid)], original['templates'][str(tid)])
            enemy = data['enemies'][str(row['enemy_id'])]
            self.assertEqual((enemy['level_min'], enemy['level_max'], enemy['pet_flag']), (1,1,1))
            self.assertEqual(enemy['max_count'], original['enemies'][str(source)]['max_count'])
            self.assertEqual(len([p for p in classic if p['template_id'] == tid]), 1)
        for tid in [271,272,273,274]:
            self.assertEqual(len([p for p in classic if p['template_id'] == tid]), 1)
        for tid in [753,757,758,966,161,162,163,164]:
            self.assertFalse(any(e['template_id'] == tid for e in spec['encounters']))

if __name__=='__main__':unittest.main()
