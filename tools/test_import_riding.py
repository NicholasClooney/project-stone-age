import json
import tempfile
import unittest
from pathlib import Path
from import_riding import mappings, playable, select, species_names

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
