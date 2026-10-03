"""Pinned original reward predicates and opt-in UID selection import contract."""
import copy
import hashlib
import json
from pathlib import Path
import unittest
import tempfile
from quest_import_common import load_quest_module, WIND_REWARD_SCRIPT, WIND_REWARD_SHA

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'references/chenmingbiao-stone-age'

def selection_spec():
    paths = ['gmsv/data/itemset.txt','gmsv/data/jobdaily.txt',
             'gmsv/data/npc/sainasu/event/genou/genou.create',
             'gmsv/data/npc/' + WIND_REWARD_SCRIPT]
    return dict(version=1,id='transmigration-wind-selection',reference_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',
        sources={p:hashlib.sha256((REFERENCE/p).read_bytes()).hexdigest() for p in paths},
        creates=[paths[2]], scripts={WIND_REWARD_SCRIPT:dict(branches=list(range(6)),events=[41,42],
            branch_reviews={str(i):{'project_pet_selection':True} for i in range(3)})},
        items=[2758,73,173,375,574,774,973,1075,2695,67,167,271,473,676,872,1175,2691,71,171,372,571,772,972,1074,2694],
        reward_enemies=[],jobs=[])

class SelectionImport(unittest.TestCase):
    def test_source_and_thresholds(self):
        module=load_quest_module(REFERENCE,selection_spec())
        self.assertEqual(len(module['npcs']),2)
        branches=module['npcs'][0]['branches']
        self.assertEqual([b['source_branch_index'] for b in branches],list(range(6)))
        self.assertEqual(branches[0]['condition'],'LV>0&ENDEV=42&ENDEV=4&PET>60-95')
        self.assertIn(',&ITEM=2758LV>0',branches[0]['source_condition'])
        self.assertEqual([b['actions']['DelPet'] for b in branches[:3]],['PET>59-95*1','PET>42-95*1','PET>0-95*1'])
        self.assertEqual([len(b['actions']['GetRandItem'].split(',')) for b in branches[:3]],[8,13,14])
        self.assertTrue(all(b.get('project_pet_selection') is True for b in branches[:3]))
        self.assertTrue(all(b['source_actions']==b['actions'] for b in branches[:3]))
        self.assertTrue(all('project_pet_selection' not in b for b in branches[3:]))
    def test_changed_source_bytes(self):
        spec=selection_spec()
        with tempfile.TemporaryDirectory(prefix='wind-source-') as directory:
            root=Path(directory)
            for name in spec['sources']:
                target=root/name;target.parent.mkdir(parents=True,exist_ok=True)
                if name=='gmsv/data/npc/'+WIND_REWARD_SCRIPT:
                    target.write_bytes((REFERENCE/name).read_bytes()+b'\n')
                else:target.symlink_to(REFERENCE/name)
            with self.assertRaisesRegex(ValueError,'Unreviewed source change'):
                load_quest_module(root,spec)
    def test_fail_closed(self):
        for mutation in ['sha','other_branch','type','unknown']:
            spec=selection_spec()
            review=spec['scripts'][WIND_REWARD_SCRIPT]
            if mutation=='sha':spec['sources']['gmsv/data/npc/'+WIND_REWARD_SCRIPT]='0'*64
            if mutation=='other_branch':review['branch_reviews']['3']={'project_pet_selection':True}
            if mutation=='type':review['branch_reviews']['0']['project_pet_selection']=1
            if mutation=='unknown':review['branch_reviews']['0']['extra']=True
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):load_quest_module(REFERENCE,spec)

if __name__=='__main__':
    import sys
    if '--fixture' in sys.argv:
        path=ROOT/'client/tests/fixtures/transmigration-wind-selection.json'
        path.write_text(json.dumps(load_quest_module(REFERENCE,selection_spec()),ensure_ascii=False,indent=2)+'\n')
    else:unittest.main()
