import copy
import hashlib
import json
import unittest
from pathlib import Path
from import_early_quests import catalog
from quest_item_effects import MAGIC_SHA, MAGIC_SOURCE

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'

class ItemEffectsTests(unittest.TestCase):
    def test_all_reward_source_metadata_is_reproducible(self):
        fixture=json.loads((ROOT/'client/tests/fixtures/original-item-effects.json').read_text())
        self.assertEqual(catalog(REF,fixture['manifest'])['items'],fixture['items'])
        self.assertEqual(hashlib.sha256((REF/MAGIC_SOURCE).read_bytes()).hexdigest(),MAGIC_SHA)
        for item in fixture['items'].values():
            for effect in item['effects']:
                self.assertFalse(effect['active'])
                self.assertTrue(effect['raw'] and effect['source']['columns'] and effect['reason'])
                self.assertEqual(effect['source']['line'],item['source_line'])
        for ident,magic in [(2688,12),(2689,2),(2690,22),(2765,300)]:
            effect=next(e for e in fixture['items'][str(ident)]['effects'] if e['type']=='magic')
            self.assertEqual(int(effect['raw']['magicid']),magic)
            self.assertEqual(effect['definition']['sha256'],MAGIC_SHA)
        medicine=fixture['items']['2450']['effects'][0]
        self.assertEqual(medicine['raw'],dict(function='ITEM_useRessurect',argument='500'))
        self.assertEqual(fixture['items']['1357']['stats_source'][0]['raw'],dict(min='5',max='5'))
        self.assertEqual(fixture['items']['2482']['stats_source'][0]['raw'],dict(min='33',max='37'))
        self.assertEqual(fixture['items']['2421']['effects'],[])
        self.assertEqual(fixture['items']['2421']['stats_source'],[])

    def test_real_supported_herb_use_not_marked_inactive(self):
        spec=json.loads((ROOT/'tools/early_quest_sources.json').read_text())
        # Current primary manifest declares the source herb runtime explicitly.
        result=catalog(REF,spec)
        herb=result['items']['2401']
        self.assertTrue(herb['effects'][0]['active'])
        self.assertEqual(herb['effects'][0]['scope'],'field')

if __name__=='__main__':unittest.main()
