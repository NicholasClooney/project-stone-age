import json
import tempfile
import unittest
from pathlib import Path
from import_riding import mappings, playable, ride_codes, select, species_names

TABLE = '''
tagRidePetTable ridePetTable[296] =
{
\t{ 101000, 100000, 100352, 331 },
\t{ 101004, 100000, 100329, 309 },
\t{ 101006, 100010, 100330, 310 },
//\t{ 199999, 100010, 100330, 310 },
#ifdef _GM_METAMO_RIDE
\t{ 101000, 100700, 100352, 331 },
#endif
\t{ 101010, 100020, 100396, 483 },
\t{ 101040, 100080, 100396, 483 },
\t{ 101179, 101177, 101178, 1804},
\t{ 100420, 100710, 100369, 348 },
\t{ 109999, 100000, 100329, 309 },
};
'''


LEADER_TABLE = '''
\t{ 101000, 100000, 100352, 331 },
//\t{ 101008, 100700, 100372, 351 },
//\t{ 101009, 100705, 100373, 352 },
\t{ 101010, 100020, 100396, 483 },
//\t{ 101018, 100710, 100372, 351 },
//\t{ 101019, 100715, 100373, 352 },
//\t{ 199999, 100720, 100330, 310 },
'''


class LeaderMountTest(unittest.TestCase):
    def test_every_colour_of_a_character_rides_its_leader_mounts(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'table.c'
            path.write_text(LEADER_TABLE)
            result = mappings(path)
        for rider in [100000, 100005, 100010, 100015]:
            self.assertEqual(result[f'{rider}:100372'], dict(sprite=101008, rider=rider, pet=100372, source_enemy_id=351, leader_body=100700))
            self.assertEqual(result[f'{rider}:100373']['sprite'], 101009)
        for rider in [100020, 100025, 100030, 100035]:
            self.assertEqual(result[f'{rider}:100372']['sprite'], 101018)
            self.assertEqual(result[f'{rider}:100373']['leader_body'], 100715)
        # Only the two leader mounts are taken from commented rows.
        self.assertFalse(any(pair['pet']==100330 for pair in result.values()))
        self.assertEqual(result['100000:100352']['sprite'], 101000)


# Shape of char_base.c:433-560: a _RIDE_CF RideCodeMode (3 fields) then the
# plain one, RideNoList, RPlistMode; plus the commented leader rows.
CERTIFICATE_TABLE = LEADER_TABLE + '''
\t{ 101004, 100000, 100329, 309 },
#ifdef _RIDE_CF
tagRideCodeMode RideCodeMode[] = {
\t{ 999999, -1, RIDE_PET0 },
};
#else
tagRideCodeMode RideCodeMode[] = {
\t{ 100374, RIDE_PET0 },  /*骑宠帖拉所伊朵*/
\t{ 100288, RIDE_PET4 },  /*骑宠扬奇洛斯*/
\t{ 100372, RIDE_PET8 },  /*骑宠左迪洛斯*/
\t{ 100329, RIDE_PET3 },
\t{ 100369, RIDE_PET13 }, /*镲宠霍尔克*/
};
#endif
tagRideNoList RideNoList[] = {
\t{{ 101305, 101309, 101008, 555555, 100420},0},\t//row 0
\t{{ 101313, 101317, 101018, 555555, -1},0},\t//row 1
};
tagRidePetList RPlistMode[] = {
\t{ 100000, 0, 1 }, { 100005, 0, 1 }, { 100700, 0, 1 },
\t{ 100020, 1, 1 }, { 100035, 1, 1 },
};
'''


class CertificateMountTest(unittest.TestCase):
    def result(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'table.c'
            path.write_bytes(CERTIFICATE_TABLE.encode('gb18030'))
            return mappings(path)

    def test_ride_no_list_gives_the_per_character_composite(self):
        result = self.result()
        self.assertEqual(result['100000:100288'], dict(sprite=101309, rider=100000, pet=100288, certificate=4))
        self.assertEqual(result['100005:100374']['sprite'], 101305)
        self.assertEqual(result['100035:100288']['sprite'], 101317)
        self.assertEqual(result['100000:100369']['sprite'], 100420)
        # -1 means no composite; RPlistMode lacks 100010; leaders are not riders.
        self.assertNotIn('100020:100369', result)
        self.assertNotIn('100010:100288', result)
        self.assertFalse(any(pair['rider'] == 100700 for pair in result.values()))

    def test_ride_pet_table_rows_win(self):
        # family.c:2347 tries ridePetTable before the certificate lookup.
        result = self.result()
        self.assertEqual(result['100000:100329'], dict(sprite=101004, rider=100000, pet=100329, source_enemy_id=309))
        self.assertEqual(result['100005:100329']['sprite'], 555555)

    def test_certificate_leader_mounts_record_the_leader_art(self):
        result = self.result()
        self.assertEqual(result['100000:100372'], dict(sprite=101008, rider=100000, pet=100372, certificate=8, leader_body=100700))
        self.assertEqual(result['100020:100372']['sprite'], 101018)
        # Colour variants absent from RPlistMode still get the leader fallback.
        self.assertEqual(result['100010:100372']['source_enemy_id'], 351)

    def test_the_plain_ride_code_table_is_used(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'table.c'
            path.write_bytes(CERTIFICATE_TABLE.encode('gb18030'))
            codes = ride_codes(path.read_bytes().decode('gb18030'))
        self.assertEqual(codes[:2], [(100374, 0, '骑宠帖拉所伊朵'), (100288, 4, '骑宠扬奇洛斯')])
        self.assertEqual(len(codes), 5)

    def test_certificate_names_follow_the_ride_code_comment(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            rows = []
            for name, template, sprite in [('猪雀', 39, 100370), ('奇宝', 294, 100370), ('扬奇洛斯', 92, 100288)]:
                base = [''] * 39
                base[0], base[6], base[36] = name, str(template), str(sprite)
                rows.append(','.join(base))
            (root/'enemy.txt').write_bytes(b'')
            (root/'enemybase.txt').write_bytes(('\n'.join(rows)+'\n').encode('gb18030'))
            pairs = {'100000:100370': dict(sprite=100425, rider=100000, pet=100370, certificate=12),
                     '100000:100288': dict(sprite=101309, rider=100000, pet=100288, certificate=4)}
            names = species_names(root, pairs, {100370: '骑宠奇宝', 100288: '骑宠扬奇洛斯'})
        self.assertEqual(names, {'100370': '奇宝', '100288': '扬奇洛斯'})


class RidingImportTest(unittest.TestCase):
    def table(self, folder):
        path = Path(folder)/'table.c'
        path.write_text(TABLE)
        return path

    def test_every_player_pair_for_every_pet(self):
        with tempfile.TemporaryDirectory() as folder:
            result = mappings(self.table(folder))
        self.assertEqual(set(result), {'100000:100352', '100000:100329', '100010:100330', '100020:100396', '100080:100396'})
        self.assertEqual(result['100020:100396'], dict(sprite=101010, rider=100020, pet=100396, source_enemy_id=483))
        self.assertNotIn('100000:100330', result)

    def test_first_table_match_wins(self):
        with tempfile.TemporaryDirectory() as folder:
            result = mappings(self.table(folder))
        self.assertEqual(result['100000:100329']['sprite'], 101004)

    def test_leader_and_special_riders_are_not_player_pairs(self):
        with tempfile.TemporaryDirectory() as folder:
            riders = {pair['rider'] for pair in mappings(self.table(folder)).values()}
        self.assertFalse(riders & {100700, 100710, 101177})

    def test_unplayable_riders_are_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            pairs = mappings(self.table(folder))
            catalog = Path(folder)/'catalog.json'
            catalog.write_text(json.dumps(dict(characters={'100000': {}, '100010': {}, '100020': {}})))
            kept, unavailable = select(pairs, playable(catalog))
            self.assertIsNone(playable(Path(folder)/'missing.json'))
        self.assertEqual(len(kept), 4)
        self.assertEqual([(p['rider'], p['reason']) for p in unavailable], [(100080, 'rider appearance is not a playable character in this import')])
        self.assertEqual(select(pairs, None), (pairs, []))

    def test_names_follow_the_source_enemy_template(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            enemy = [''] * 14
            enemy[0], enemy[3], enemy[4] = 'enemy', '309', '193'
            base = [''] * 39
            base[0], base[6] = '格鲁西斯', '193'
            (root/'enemy.txt').write_bytes((','.join(enemy)+'\n').encode('gb18030'))
            (root/'enemybase.txt').write_bytes((','.join(base)+'\n').encode('gb18030'))
            pairs = {'100000:100329': dict(sprite=101004, rider=100000, pet=100329, source_enemy_id=309)}
            self.assertEqual(species_names(root, pairs), {'100329': '格鲁西斯'})
            self.assertEqual(species_names(root/'missing', pairs), {})


if __name__ == '__main__':
    unittest.main()
