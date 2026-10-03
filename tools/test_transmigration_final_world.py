"""Original declarations are the oracle; imported world must match exactly."""
import hashlib
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
class FinalWorld(unittest.TestCase):
    def test_source_declarations_and_exact_imported_union(self):
        spec=json.loads((ROOT/'tools/transmigration_final_quest_sources.json').read_text())
        rows=json.loads((ROOT/'client/tests/fixtures/transmigration-final-portals.json').read_text())['portals']
        for p in {e['source'] for e in rows}:
            self.assertEqual(hashlib.sha256((REF/p).read_bytes()).hexdigest(),spec['sources'][p])
        for e in rows:
            text=(REF/e['source']).read_bytes().decode('gb18030')
            if 'source_create_index' in e:
                match=list(re.finditer(r'\{([^}]+)\}',text))[e['source_create_index']]
                fields=dict(l.strip().split('=',1) for l in match[1].splitlines() if '=' in l and not l.lstrip().startswith('#'))
                self.assertEqual(text[:match.start()].count('\n')+1,e['source_line'])
                self.assertEqual(fields['floorid'],str(e['from_map']))
                self.assertEqual(fields['borncorner'],','.join(map(str,e['cell']*2)))
                self.assertEqual(fields['enemy'],'npcgen_warp|'+'|'.join(map(str,[e['to_map'],*e['target']])))
            else:
                self.assertEqual(text.splitlines()[e['source_line']-1],'NONE:NULL:'+','.join(map(str,[e['from_map'],*e['cell']]))+':'+','.join(map(str,[e['to_map'],*e['target']]))+':NULL')
        key=lambda p:(p['from_map'],*p['cell'],p['to_map'],*p['target'])
        self.assertEqual(len(rows),262)
        expected={key(p) for p in rows};self.assertEqual(len(expected),137)
        world=json.loads((ROOT/'client/assets/legacy/world/manifest.json').read_text())
        actual=[p for p in world['portals'] if p['from_map'] in range(32001,32022) or p['to_map'] in range(32001,32022)]
        self.assertEqual({key(p) for p in actual},expected)
        self.assertEqual(len(actual),137)
        self.assertFalse(any(p.get('gate_source') for p in actual))
        # Original source declares five return cells inside collision geometry;
        # preserve these unavailable declarations, never clear original walls.
        blocked={(32021,x,y,32021,31,53) for x,y in [(28,47),(29,47),(28,48),(29,48),(34,49)]}
        self.assertEqual({key(p) for p in actual if p.get('disabled')},blocked)
        from import_world import read_map
        from map_file import load_map
        raw=read_map(REF/spec['world']['map_sources']['32021']['path'])
        imported=load_map(ROOT/'client/assets/legacy/world/32021.map')
        for _,x,y,_,_,_ in blocked:
            self.assertEqual(raw[5][y*raw[2]+x],2)
            self.assertTrue(imported['blocked'][y*imported['width']+x])
        for m in range(32001,32022):
            record=world['provenance']['maps'][str(m)]
            self.assertEqual(record['sha256'],spec['world']['map_sources'][str(m)]['sha256'])
            self.assertEqual(record['missing_graphics'],[])
if __name__=='__main__':unittest.main()
