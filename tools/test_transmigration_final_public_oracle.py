"""The final addition must preserve the entire independently frozen prior union."""
import copy
import hashlib
import json
import re
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
class FinalOracle(unittest.TestCase):
    def setUp(self):
        self.public=json.loads((ROOT/'client/tests/fixtures/public-quest-npcs.json').read_text())
    def test_prior_297_338_union_is_byte_semantically_preserved(self):
        old=copy.deepcopy(self.public)
        final_ids={n['id'] for n in old['groups']['transmigration-final']['npcs']}
        old['active_npc_ids']=[i for i in old['active_npc_ids'] if i not in final_ids]
        old['enabled_events']=[e for e in old['enabled_events'] if e not in [48,49,50,51,52]]
        del old['groups']['transmigration-final']
        del old['reviewed_source_extensions']['transmigration-final']
        old['item_ids'].remove(2138)
        self.assertEqual(sum(len(g['npcs']) for g in old['groups'].values()),297)
        self.assertEqual(len(old['item_ids']),338)
        frozen={k:old[k] for k in ['groups','item_ids','active_npc_ids','enabled_events','unplaced_area_npcs','reviewed_source_extensions']}
        digest=hashlib.sha256(json.dumps(frozen,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        self.assertEqual(digest,'b81d6f249e75b53427652e1d16ce61cb25607ed0720c3cc962c7206e84663a55')
    def test_exact_final_original_identity_branch_union(self):
        group=self.public['groups']['transmigration-final']
        self.assertEqual(group['enabled_events'],[48,49,50,51,52])
        self.assertEqual(set(n['id'] for n in group['npcs']) & set(self.public['active_npc_ids']),set(n['id'] for n in group['npcs']))
        self.assertEqual(len(group['npcs']),17)
        ids=[n['id'] for g in self.public['groups'].values() for n in g['npcs']]
        self.assertEqual(len(ids),314);self.assertEqual(len(set(ids)),314)
        self.assertEqual(self.public['reviewed_counts']['catalog_items'],339)
        self.assertEqual(self.public['item_ids'].count(2138),1)
        for npc in group['npcs']:
            text=(REF/npc['source_create']).read_bytes().decode('gb18030')
            block=re.findall(r'\{([^}]+)\}',text)[npc['source_create_index']]
            source=dict(line.strip().split('=',1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
            self.assertEqual(source['enemy'].split('|file:')[1],npc['source_script'])
            self.assertEqual(int(source['floorid']),npc['map_id'])
            self.assertEqual(list(map(int,source.get('borncorner',source.get('borncenter')).split(',')))[:2],npc['cell'])
            self.assertEqual([source['name'],int(source['graphicname']),int(source['dir'])],[npc['name'],npc['graphic'],npc['facing']])
            if npc['source_script'].startswith('giiru/'):
                text=(REF/'gmsv/data/npc'/npc['source_script']).read_bytes().decode('gb18030')
                blocks=re.findall(r'^EventNo:([^\n]+)\n(.*?)^EventEnd\s*$',text,re.M|re.S)
                indices=[b['source_branch_index'] for b in npc['branches']]
                self.assertEqual(indices,list(range(1,8)) if npc['source_script'].endswith('05') else [0,1])
                for b in npc['branches']:
                    event,block=blocks[b['source_branch_index']]
                    fields=dict(line.split(':',1) for line in block.splitlines() if ':' in line)
                    self.assertEqual((b['event'],b['type'],b['condition']),(int(event),fields['TYPE'],fields['EVENT']))
                    self.assertEqual(b['actions'],{k:fields[k] for k in ['GetItem','DelItem','EndSetFlg','Charm'] if k in fields})
if __name__=='__main__':unittest.main()
