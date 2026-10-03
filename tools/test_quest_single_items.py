import copy
import csv
import hashlib
import unittest
from pathlib import Path
from import_early_quests import catalog
from quest_single_items import AUDIT, SOURCES, pile_metadata, reviewed_single_items

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'references/chenmingbiao-stone-age'

def manifest():
    sources = dict(SOURCES)
    path = 'gmsv/data/jobdaily.txt'
    sources[path] = hashlib.sha256((REF / path).read_bytes()).hexdigest()
    return dict(reference_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',
                sources=sources, creates=[], scripts=[], items=[int(i) for i in AUDIT['items']],
                single_item_pile_reviews=copy.deepcopy(list(AUDIT['items'].values())))

class SingleItemsTests(unittest.TestCase):
    def test_all_34_source_rows_and_created_quantity(self):
        items = catalog(REF, manifest())['items']
        self.assertEqual(len(items), 34)
        for ident, item in items.items():
            self.assertEqual(item['raw_columns'][24:26], ['', '1'])
            self.assertEqual(item['source_line'], AUDIT['items'][ident]['source_line'])
            self.assertFalse(item['stackable'])
            self.assertEqual(item['source_pile']['creation_quantity'], 1)
            self.assertFalse(item['source_pile']['stacking_supported'])
            self.assertIn('每件占一格', item['description'])

    def test_default_then_nonempty_override_then_single_instance(self):
        # SHA lock pins the complete C control flow; these assertions identify its anchors.
        source = (REF / 'gmsv/item/item.c').read_text(encoding='gb18030')
        self.assertRegex(source, r'\{\s*"upin"\s*,\s*1\s*,\s*ITEM_USEPILENUMS\s*\}')
        self.assertRegex(source, r'\{\s*"canpile"\s*,\s*0\s*,\s*ITEM_CANBEPILE\s*\}')
        self.assertIn('ITEM_getDefaultItemSetting', source)
        self.assertIn('ITEM_makeItemAndRegist', source)
        for path, sha in SOURCES.items():
            self.assertEqual(hashlib.sha256((REF / path).read_bytes()).hexdigest(), sha)

    def test_explicit_pile_without_declaration_rejected(self):
        spec = manifest(); spec.pop('single_item_pile_reviews')
        with self.assertRaises(ValueError): catalog(REF, spec)

    def test_source_locks_required(self):
        for path in SOURCES:
            spec = manifest(); spec['sources'].pop(path)
            with self.assertRaises(ValueError): reviewed_single_items(REF, spec)

    def test_unknown_changed_duplicate_and_unused_declarations_rejected(self):
        mutations = [dict(id=99999), dict(creation_quantity=2), dict(columns=['2', '1']),
                     dict(source_line=1), dict(audit='unreviewed')]
        for changes in mutations:
            spec = manifest(); spec['single_item_pile_reviews'][0].update(changes)
            with self.assertRaises(ValueError): reviewed_single_items(REF, spec)
        spec = manifest(); spec['single_item_pile_reviews'].append(spec['single_item_pile_reviews'][0])
        with self.assertRaises(ValueError): reviewed_single_items(REF, spec)
        spec = manifest(); spec['items'].pop(0)
        with self.assertRaises(ValueError): reviewed_single_items(REF, spec)

    def test_exact_source_columns_and_line_required(self):
        rows = list(csv.reader((REF / 'gmsv/data/itemset.txt').read_text(encoding='gb18030').splitlines()))
        review = AUDIT['items']['1238']; row = rows[review['source_line'] - 1]
        for count in ['0', '1', '2', ' ']:
            changed = row.copy(); changed[24] = count
            with self.assertRaises(ValueError): pile_metadata(review, changed, review['source_line'])
        with self.assertRaises(ValueError): pile_metadata(review, row, review['source_line'] + 1)

if __name__ == '__main__': unittest.main()
