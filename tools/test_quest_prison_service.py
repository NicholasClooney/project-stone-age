"""Service v1.1 identities checked against independently captured source blocks."""
import copy
import json
import unittest
from pathlib import Path
from quest_import_common import load_quest_module
from quest_prison_service import REVIEW,parse,is_reviewed_npc
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
class PrisonServices(unittest.TestCase):
    def setUp(self):
        self.spec=json.loads((ROOT/'tools/transmigration_final_quest_sources.json').read_text())
        self.texts={p:(REF/p).read_bytes().decode('gb18030') for p in self.spec['sources']}
        self.audit=json.loads((ROOT/'client/tests/fixtures/transmigration-prison-source.json').read_text())
    def test_five_complete_source_identities_and_payload(self):
        self.assertEqual(REVIEW['version'],'1.1')
        self.assertEqual([a['source_script'] for a in REVIEW['actors']], ['genout/wpm_117_6_5']+['genout/wpm_110_37_'+str(y) for y in [20,24,28,32]])
        module=load_quest_module(REF,self.spec)
        actual=[n for n in module['npcs'] if n.get('kind')=='original_prison']
        self.assertEqual(len(actual),5)
        for expected in REVIEW['actors']:
            old=next(a for a in self.audit['source_actors'] if a.get('script')==expected['source_script'])
            fields=old['fields'];source=dict(line.split(':',1) for line in old['source_text'].splitlines() if ':' in line)
            self.assertEqual(expected['source_fields'],source)
            self.assertEqual(expected['source_create_index'],old['source_create_index'])
            self.assertEqual(expected['source_create'],old['source_create'])
            self.assertEqual([expected['graphic'],expected['facing'],expected['name']], [int(fields['graphicname']),int(fields['dir']),fields['name']])
            self.assertEqual(expected['cell'],list(map(int,fields['borncorner'].split(',')))[:2])
            self.assertEqual(expected['map_id'],int(fields['floorid']))
            self.assertEqual(expected['prison'],dict(role='guard' if expected['map_id']==117 else 'guide',warp=source['WARP'],condition=source['FREE'],money=source['MONEY'],del_item=source.get('DelItem','')))
            npc=next(n for n in actual if n['id']==expected['id'])
            self.assertTrue(is_reviewed_npc(npc,'transmigration-final'))
            self.assertEqual({k:npc[k] for k in expected},expected)
            self.assertNotIn('prison_role',npc)
    def test_substitution_and_sha_rejected(self):
        for expected in REVIEW['actors']:
            script=expected['source_script'];old=next(a for a in self.audit['source_actors'] if a.get('script')==script)
            args=[self.spec,self.texts,script,old['source_create'],old['source_create_index'],old['fields'],self.spec['handlers'][script]]
            parse(*args)
            for index,value in [(3,'fake.create'),(4,999),(5,dict(old['fields'],graphicname='1'))]:
                bad=copy.deepcopy(args);bad[index]=value
                with self.assertRaises(ValueError):parse(*bad)
            bad=copy.deepcopy(args);bad[1]['gmsv/data/npc/'+script]+='\n'
            with self.assertRaisesRegex(ValueError,'SHA'):parse(*bad)
            self.assertFalse(is_reviewed_npc(expected,'other-module'))
            changed=copy.deepcopy(expected);changed['prison']['money']='0'
            self.assertFalse(is_reviewed_npc(changed,'transmigration-final'))
if __name__=='__main__':unittest.main()
