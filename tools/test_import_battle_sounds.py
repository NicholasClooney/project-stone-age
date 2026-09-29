import json
import tempfile
import unittest
from pathlib import Path
from import_battle_sounds import fill, hit_se, parse_table, used_sounds

TABLE = r'''
	{    1, "data\\se\\sap_01.wav", 85, 0, 0 /*, "a"*/ },
//x	{   11, "data\\se\\sap_99.wav", 105, 7, 0 },
	{   11, "data\\se\\sap_11.wav", 105, 0, 0 },
	{  203,	"data\\se\\sas_03.wav", 75, 0, 0 },
	{  130,"data\\se\\sap_14.wav",100, 0, 0	} ,
	{  250, "data\\se\\sad_01.wav", 90, 0, 0 },
	{  254, "data\\se\\sad_05.wav", 90, 0, 0 },
'''


class TableTest(unittest.TestCase):
    def test_rows_are_read_and_comments_skipped(self):
        table = parse_table(TABLE)
        self.assertEqual(table[1], 'sap_01.wav')
        self.assertEqual(table[11], 'sap_11.wav')
        self.assertEqual(table[203], 'sas_03.wav')
        self.assertEqual(table[130], 'sap_14.wav')

    def test_hit_markers_follow_play_damage(self):
        self.assertEqual(hit_se(10000), 250)
        self.assertEqual(hit_se(10101), 254)
        self.assertEqual(hit_se(10004), 252)
        self.assertIsNone(hit_se(10005))
        self.assertEqual(hit_se(10099), 250)


class FillTest(unittest.TestCase):
    def test_used_ids_are_mapped_and_copied(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            se = root / 'se'
            se.mkdir()
            for name in ('sap_01.wav', 'sad_01.wav', 'sad_05.wav'):
                (se / name).write_bytes(b'RIFF')
            battle = root / 'battle'
            battle.mkdir()
            frames = [{'sound': 1}, {'sound': 10101}, {'sound': 10000}, {'sound': 77}, {'sound': 10005}]
            manifest = {'characters': {'100373': {'0_3': {'frames': frames}}}, 'frame_sounds': {'211': 'audio/sas_11.wav'}}
            (battle / 'manifest.json').write_text(json.dumps(manifest, indent=2))
            self.assertEqual(used_sounds(manifest), {1, 250, 254, 77})
            count, missing = fill(battle / 'manifest.json', parse_table(TABLE), se)
            written = json.loads((battle / 'manifest.json').read_text())
            self.assertEqual(written['frame_sounds'], {'1': 'audio/sap_01.wav', '211': 'audio/sas_11.wav', '250': 'audio/sad_01.wav', '254': 'audio/sad_05.wav'})
            self.assertEqual(missing, [77])
            self.assertTrue((battle / 'audio' / 'sad_05.wav').exists())
            self.assertIn('\n', (battle / 'manifest.json').read_text())


if __name__ == '__main__':
    unittest.main()
