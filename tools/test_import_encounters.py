import json
import tempfile
import unittest
from pathlib import Path
from import_encounters import ALBUM_PETS, add_album_pets, atoi, build, choices

ROOT = Path('references/chenmingbiao-stone-age/gmsv/data')

class EncounterImportTests(unittest.TestCase):
    def test_c_integer_parser(self):
        self.assertEqual(atoi('4.50'), 4)
        self.assertEqual(atoi(' -2tail'), -2)
        self.assertEqual(atoi(''), 0)

    def test_weighted_slots_preserve_original_ids(self):
        self.assertEqual(choices(['7','8']+['']*8+['1','0']+['']*8,0,10), [{'id':7,'weight':1},{'id':8,'weight':0}])

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

    def test_shipped_album_pets_have_unique_albums_and_sprites(self):
        pets=json.loads(ALBUM_PETS.read_text())['pets']
        self.assertEqual(len({p['album'] for p in pets}),len(pets))
        self.assertEqual(len({p['sprite'] for p in pets}),len(pets))
        self.assertTrue(all(100000<p['sprite']<110000 and 28000<p['face']<29000 for p in pets))

if __name__=='__main__':unittest.main()
