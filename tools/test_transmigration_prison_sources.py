"""Source-only prison/exit audit. This never enables a map, portal or toll."""
import hashlib
import json
import re
import struct
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'

class PrisonSources(unittest.TestCase):
    def setUp(self):
        self.fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-prison-source.json').read_text())

    def test_every_locked_source_and_map(self):
        for path,sha in self.fixture['sources'].items():
            self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),sha,path)
        for ident,record in self.fixture['map_sources'].items():
            raw=(REF/record['path']).read_bytes()
            self.assertEqual(raw[:6],b'LS2MAP')
            self.assertEqual(struct.unpack_from('>H',raw,6)[0],int(ident))
            self.assertEqual(hashlib.sha256(raw).hexdigest(),record['sha256'])
        for actor in self.fixture['source_actors']:
            text=(REF/actor['source_create']).read_bytes().decode('gb18030')
            m=list(re.finditer(r'\{([^}]+)\}',text))[actor['source_create_index']]
            fields=dict(l.strip().split('=',1) for l in m[1].splitlines() if '=' in l and not l.lstrip().startswith('#'))
            self.assertEqual(fields,actor['fields'])
            self.assertEqual(text[:m.start()].count('\n')+1,actor['source_line'])
            if 'script' in actor:
                self.assertEqual((REF/('gmsv/data/npc/'+actor['script'])).read_bytes().decode('gb18030'),actor['source_text'])

    def test_every_original_portal_declaration(self):
        rows=self.fixture['ordinary_portals']
        self.assertEqual(len(rows),101)
        self.assertEqual(len({(e['from_map'],*e['cell'],e['to_map'],*e['target']) for e in rows}),53)
        for e in rows:
            text=(REF/e['source']).read_bytes().decode('gb18030')
            if 'source_create_index' in e:
                m=list(re.finditer(r'\{([^}]+)\}',text))[e['source_create_index']]
                self.assertEqual(text[:m.start()].count('\n')+1,e['source_line'])
                self.assertIn('floorid='+str(e['from_map']),m[1])
                self.assertIn('enemy=npcgen_warp|'+'|'.join(map(str,[e['to_map'],*e['target']])),m[1])
                self.assertIn('borncorner='+','.join(map(str,[*e['cell'],*e['cell']])),m[1])
            else:
                self.assertEqual(text.splitlines()[e['source_line']-1], 'NONE:NULL:'+','.join(map(str,[e['from_map'],*e['cell']]))+':'+','.join(map(str,[e['to_map'],*e['target']]))+':NULL')

    def test_exact_toll_identity_and_original_timing(self):
        gate=next(a for a in self.fixture['source_actors'] if a.get('script')=='genout/wpm_117_6_5')
        self.assertEqual((gate['source_create_index'],gate['source_line']), (18,222))
        self.assertEqual((gate['fields']['floorid'],gate['fields']['borncorner'],gate['fields']['graphicname'],gate['fields']['dir']),('117','6,5,6,5','16204','4'))
        self.assertIn('WARP:110,23,27',gate['source_text'])
        self.assertIn('FREE:\nMONEY:1',gate['source_text'])
        text=(REF/'gmsv/npc/npc_warpman.c').read_bytes().decode('gb18030')
        self.assertIn('if (money>=10) money*=0.9;',text)
        self.assertIn('else if( money == 0 )',text)
        self.assertIn('CHAR_warpToSpecificPoint(toindex,117,225,13);',text)
        self.assertLess(text.index('money*=0.9'),text.index('CHAR_setWorkInt( toindex , CHAR_WORKSHOPRELEVANTTRD , money )'))
        self.assertIn('CHAR_DelGold( talkerindex, CHAR_getWorkInt(talkerindex,CHAR_WORKSHOPRELEVANTTRD ));',text)
        cases={c['gold']:c for c in self.fixture['fee_cases']}
        self.assertEqual((cases[0]['quoted_fee'],cases[0]['destination'],cases[0]['phase']),(0,[117,225,13],'initial_talk'))
        self.assertEqual([cases[i]['quoted_fee'] for i in range(1,11)],[1,2,3,4,5,6,7,8,9,9])
        self.assertEqual([cases[i]['quoted_fee'] for i in [11,19,20,99,100,1000000000]],[9,17,18,89,90,900000000])

    def test_exact_existing_map_impact_not_broad_activation(self):
        impact=self.fixture['import_impact']
        self.assertEqual(len(impact),29)
        current=[e for e in impact if e['origin_currently_imported']]
        expected={(32020,x,y) for x,y in [(20,8),(19,7),(20,7),(21,7),(19,6),(20,6),(21,6),(19,5),(20,5),(21,5)]}
        expected|={(21214,30,y) for y in range(33,40)}|{(21014,15,4)}
        self.assertEqual({(e['from_map'],*e['cell']) for e in current},expected)
        self.assertTrue(all(e['would_pass_map_membership_if_117_added'] for e in current))
        self.assertEqual({e['from_map'] for e in impact if not e['origin_currently_imported']},{5510,5576,30691,30692,30693,30694})
        spec=json.loads((ROOT/'tools/transmigration_final_quest_sources.json').read_text())
        self.assertFalse({'110','117'} & set(spec['world']['map_sources']))
        self.assertNotIn('genout/wpm_117_6_5',spec['handlers'])
        self.assertEqual(json.loads((ROOT/'client/data/quests/transmigration-final.json').read_text())['enabled_events'],[])

if __name__=='__main__':unittest.main()
