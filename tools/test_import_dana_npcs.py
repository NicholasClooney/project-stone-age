import unittest
import json
import hashlib
from collections import Counter
from pathlib import Path
from import_dana_npcs import definitions

class DanaDefinitions(unittest.TestCase):
    def test_frozen_public_population_includes_only_reviewed_quests(self):
        frozen=json.loads(Path('client/tests/fixtures/dana-public-actors.json').read_text())
        reference=Path('references/chenmingbiao-stone-age')
        for path,sha in frozen['sources'].items():
            self.assertEqual(hashlib.sha256((reference/path).read_bytes()).hexdigest(),sha)
        public=json.loads(Path('client/tests/fixtures/public-quest-npcs.json').read_text())
        expected=[]
        for group in public['groups'].values():
            for npc in group['npcs']:
                if npc['map_id'] in [5100,5101,5103,5105,5106]:
                    expected.append(dict({key:npc[key] for key in ['map_id','cell','name','graphic','facing']},role='quest',id=npc['id']))
        self.assertEqual(sorted([n for n in frozen['actors'] if n['role']=='quest'],key=lambda n:n['id']),sorted(expected,key=lambda n:n['id']))
        self.assertEqual({n['id'] for n in expected},{'giiru/event/event30_3','giiru/event/sink/sink07@5106:26:15'})
        fields=['map_id','cell','name','graphic','facing','role']
        original=[{key:npc[key] for key in fields} for npc in definitions(reference)]
        self.assertEqual([n for n in frozen['actors'] if n['role']!='quest'],original)
        self.assertEqual(Counter(n['map_id'] for n in frozen['actors']),{5100:2,5101:5,5103:6,5105:2,5106:7})

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
