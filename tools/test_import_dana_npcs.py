import unittest
from collections import Counter
from pathlib import Path
from import_dana_npcs import definitions

class DanaDefinitions(unittest.TestCase):
    def test_reviewed_source_population(self):
        rows=list(definitions(Path('references/chenmingbiao-stone-age')))
        self.assertEqual(Counter(r['map_id'] for r in rows),{5100:2,5101:5,5103:6,5105:2,5106:5})
        self.assertEqual(Counter(r['role'] for r in rows),{'resident':5,'sign':1,'decoration':3,'deferred_service':11})
        self.assertEqual(len({(r['map_id'],*r['cell']) for r in rows}),20)
        self.assertTrue(all(r['handler'] not in ('changeevent','familyman','airplane') for r in rows))
        nurse=next(r for r in rows if r['name']=='达那的护士')
        self.assertEqual(nurse['cell'],[26,12])
        guide=next(r for r in rows if r['name']=='加美航空')
        self.assertEqual(len(guide['dialogues']),3)
        self.assertIn('1000s',next(r['text'] for r in rows if r['role']=='sign'))

if __name__=='__main__':unittest.main()
