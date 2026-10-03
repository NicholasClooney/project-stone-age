"""Independent original identities, without runtime catalog/activation as oracle."""
import copy
import hashlib
import json
import re
import unittest
from pathlib import Path
from quest_import_common import load_quest_module
from transmigration_foundation import validate

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'references/chenmingbiao-stone-age'
SPEC = ROOT / 'tools/transmigration_final_quest_sources.json'
FIXTURE = ROOT / 'client/tests/fixtures/transmigration-final-identities.json'

class FinalSources(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(SPEC.read_text())
        self.fixture = json.loads(FIXTURE.read_text())
        self.texts = {p: (REF/p).read_bytes().decode('gb18030') for p in self.spec['sources']}

    def test_exact_create_identities(self):
        self.assertEqual(len(self.fixture['npcs']), 12)
        self.assertEqual(len({a['id'] for a in self.fixture['npcs']}), 12)
        for a in self.fixture['npcs']:
            text = self.texts[a['source_create']]
            block = list(re.finditer(r'\{([^}]+)\}', text))[a['source_create_index']]
            fields = dict(line.strip().split('=', 1) for line in block[1].splitlines()
                          if '=' in line and not line.lstrip().startswith('#'))
            self.assertEqual(fields, a['source_fields'])
            self.assertEqual(text[:block.start()].count('\n')+1, a['source_line'])
            self.assertEqual(fields['enemy'], a['source_handler']+'|file:'+a['source_script'])
            self.assertEqual(int(fields['floorid']), a['map_id'])
            self.assertEqual(list(map(int, fields.get('borncorner', fields.get('borncenter')).split(',')))[:2], a['cell'])
            self.assertEqual([int(fields['graphicname']), int(fields['dir']), fields['name']], [a['graphic'], a['facing'], a['name']])
        king = next(a for a in self.fixture['npcs'] if a['source_script']=='777/ten.arg')
        self.assertEqual((king['source_create_index'], king['map_id'], king['cell'], king['graphic'], king['facing'], king['source_handler']), (5, 32021, [31,28], 100444, 4, 'npc_transmigration'))

    def test_locked_sources_maps_and_mutation(self):
        for path, digest in self.spec['sources'].items():
            self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(), digest, path)
        self.assertEqual(set(self.spec['staged_world']['map_sources']), set(map(str, range(32001,32022))))
        validate(REF, self.spec, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['reviewed_bindings'][0]['cell'][0] += 1
        with self.assertRaisesRegex(ValueError, 'actual create'):
            validate(REF, changed, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['staged_world']['map_sources']['32021']['sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError, 'SHA changed'):
            validate(REF, changed, self.texts)
        changed = copy.deepcopy(self.spec)
        changed['sources']['gmsv/data/npc/777/ten.arg'] = '0'*64
        with self.assertRaisesRegex(ValueError, 'Unreviewed source change'):
            load_quest_module(REF, changed)

    def test_original_gates_and_boss_order(self):
        for script, warp in self.fixture['gate_warps'].items():
            text = self.texts['gmsv/data/npc/'+script]
            self.assertIn('WARP:'+','.join(map(str, warp)), text.splitlines())
            self.assertIn('FREE:LV>79&ENDEV=39&ENDEV=40&ENDEV=42&ENDEV=46', text.splitlines())
            self.assertIn('MONEY:-1', text.splitlines())
        self.assertEqual(self.fixture['gate_warps']['genout/wpm_300_103_228'][0], 300)
        for script, battle in self.fixture['bosses'].items():
            fields = dict(line.split(':',1) for line in self.texts['gmsv/data/npc/'+script].splitlines() if ':' in line)
            self.assertEqual(list(map(int, fields['enemyno'].split(','))), battle['enemies'])
            self.assertEqual([int(fields[k]) for k in ['warpfl','warpx','warpy']], battle['warp'])
            self.assertEqual((fields['dieact'],fields['onebattle']), ('1','0'))

    def test_message_selection_and_closed_rewards(self):
        for script, selected in self.fixture['selected_source_branches'].items():
            # Independent extraction preserves original branch numbers, not
            # current catalog branch positions after the END53 exclusion.
            text = self.texts['gmsv/data/npc/'+script]
            branches = re.findall(r'^EventNo:.*?^EventEnd\s*$', text, re.M|re.S)
            if script.endswith('05'):
                self.assertEqual(selected, list(range(1,8)))
                self.assertIn('EventNo:53', branches[0])
                self.assertIn('GetItem:20570,20571,20572', branches[0])
                for i in selected:
                    self.assertIn('TYPE:MESSAGE', branches[i])
                    self.assertNotRegex(branches[i], r'^(GetItem|DelItem|EndSetFlg|Charm):')
            else:
                item = 2770+int(script[-2:])
                self.assertEqual(selected, [0,1])
                self.assertIn('EVENT:LV>0&ITEM='+str(item), branches[0])
                self.assertNotIn('GetItem:', branches[0])
                self.assertIn('EVENT:LV>0&ITEM!='+str(item), branches[1])
                self.assertIn('GetItem:'+str(item), branches[1])

    def test_source_handoff_does_not_enable_production(self):
        registry = json.loads((ROOT/'client/data/quest-modules.json').read_text())
        entry=next(m for m in registry['modules'] if m['id']=='transmigration-final')
        descriptor=json.loads((ROOT/entry['configuration']).read_text())
        self.assertEqual(descriptor['enabled_events'], [])
        module = load_quest_module(REF, self.spec)
        self.assertEqual(len(module['npcs']), 17)
        self.assertEqual(module, json.loads((ROOT/'client/tests/fixtures/transmigration-final-source.json').read_text()))
        self.assertEqual(set(module['items']), {'2138','2771','2772','2773','2774'})
        for ident,item in module['items'].items():
            if ident=='2138':continue
            self.assertEqual(item['raw_columns'][78:82], ['1','1','1','0'])
            self.assertTrue(item['logout_vanish'])

    def test_exact_service_texts_and_rejected_substitution(self):
        from quest_transmigration_service import parse, CREATE, SCRIPT
        actor=next(a for a in self.fixture['npcs'] if a['source_script']==SCRIPT)
        review=self.spec['handlers'][SCRIPT]
        parsed=parse(self.spec,self.texts,SCRIPT,CREATE,5,actor['source_fields'],review)
        service=parsed['transmigration']
        self.assertEqual([r['count'] for r in service['rounds']], [1,2,3,4,5])
        for row in service['rounds']:
            text=self.texts['gmsv/data/npc/'+SCRIPT].split('TENSEI:'+str(row['count'])+'\n',1)[1].split('TENSEI:',1)[0]
            expected=dict(line.split(':',1) for line in text.splitlines() if ':' in line)
            self.assertEqual(row['texts'], {k:v.replace('\\n','\n') for k,v in expected.items()})
        for key,value in [('enemy','npc_transmigration|file:777.old/ten.arg'),('floorid','32020'),('graphicname','100443')]:
            fields=dict(actor['source_fields']);fields[key]=value
            with self.assertRaises(ValueError):parse(self.spec,self.texts,SCRIPT,CREATE,5,fields,review)
        with self.assertRaises(ValueError):parse(self.spec,self.texts,SCRIPT,CREATE,6,actor['source_fields'],review)

    def test_five_complete_original_reward_pets(self):
        import csv
        module = load_quest_module(REF, self.spec)
        self.assertEqual(self.spec['reward_enemies'], [1377,1378,1379,1380,1381])
        self.assertEqual(set(module['reward_pets']), {'1377','1378','1379','1380','1381'})
        expected = [
            (1377,6,1009,6,'乌力斯坦',25,[30,24,27,24],100,[50,0,0,50],1,100252,0),
            (1378,232,1010,206,'奇娜',24,[33,28,31,11],300,[40,60,0,0],0,100344,1),
            (1379,244,1011,212,'多鲁宝',24,[33,23,24,10],240,[0,50,50,0],0,100350,1),
            (1380,272,1012,225,'洛卡伦恩',26,[22,33,24,24],300,[0,0,80,20],5,100360,1),
            (1381,304,1013,236,'帖拉所伊朵',28,[23,35,25,21],300,[0,0,50,50],2,100374,1),
        ]
        enemy_rows=list(csv.reader(self.texts['gmsv/data/enemy.txt'].splitlines()))
        base_rows=list(csv.reader(self.texts['gmsv/data/enemybase.txt'].splitlines()))
        for ident,template,line,base_line,name,initial,weights,modai,elements,slots,sprite,size in expected:
            enemy,base=enemy_rows[line-1],base_rows[base_line-1]
            self.assertEqual(list(map(int,enemy[3:7])), [ident,template,1,1])
            self.assertEqual([base[0],int(base[6]),int(base[7]),float(base[8])], [name,template,initial,4.5])
            self.assertEqual(list(map(int,base[9:13])), weights)
            self.assertEqual(list(map(int,base[15:19])), elements)
            self.assertEqual([int(base[i]) for i in [13,34,36,38]], [modai,slots,sprite,size])
            self.assertEqual(module['reward_pets'][str(ident)], dict(
                enemy_id=ident,template_id=template,species='original_'+str(template),level=1,
                name=name,initial=initial,wild_growth=4.5,weights=weights,modai=modai,
                variable_ai=0,elements=elements,skill_slots=slots,sprite=sprite,size=size,
                source='gmsv/data/enemy.txt',source_line=line,
                base_source='gmsv/data/enemybase.txt',base_source_line=base_line))
        tables={
            'samugiru':[1377,1380,1379,1378,1381],
            'marinasu':[1380,1379,1378,1377,1381],
            'jaja':[1379,1378,1377,1380,1381],
            'karutarna':[1378,1377,1380,1379,1381],
        }
        king=next(n for n in module['npcs'] if n.get('service_id')=='777/ten.arg')
        self.assertEqual({v['key']:v['presents'] for v in king['transmigration']['villages']}, tables)
        source=self.texts['gmsv/data/npc/777/ten.arg']
        for key,presents in tables.items():
            row=next(line for line in source.splitlines() if line.startswith(key+':'))
            self.assertIn('Present='+'.'.join(map(str,presents))+',Warp=',row)
        for path,digest in {
            'gmsv/data/enemy.txt':'69fc9f603cc9ee24bbc30511e6a0407254b62ba68651b71cb68f50a58f9f6629',
            'gmsv/data/enemybase.txt':'3868f26a02d60aa810a21f0abba76fe1334619862c7ba9fe21ad4417de39dc17',
            'gmsv/data/npc/777/ten.arg':'5d09f42c64a61c3220a01a5a0e82340672fb67ead03b818c4f6457421832c852',
        }.items():
            self.assertEqual(self.spec['sources'][path],digest)
            self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),digest)

    def test_normal_boss_meat_source_and_inactive_recovery(self):
        import csv
        from quest_single_items import AUDIT
        module=load_quest_module(REF,self.spec)
        meat=module['items']['2138'];row=meat['raw_columns']
        self.assertEqual(meat['source_line'],1857)
        self.assertEqual([row[i] for i in [3,10,16,18,19,22,24,25]], ['体125','ITEM_useRecovery','2138','125','20','0','','1'])
        self.assertEqual(row[78:83], ['0','0','1','1','1'])
        self.assertEqual(self.spec['single_item_pile_reviews'],[AUDIT['items']['2138']])
        self.assertEqual(meat['source_pile']['creation_quantity'],1)
        self.assertFalse(meat['stackable'])
        self.assertEqual([(e['type'],e['active']) for e in meat['effects']], [('use',False)])
        self.assertNotIn('use',meat)
        drops=module['drops'];self.assertEqual(len(drops),1)
        self.assertEqual((drops[0]['enemy_id'],drops[0]['item_id'],drops[0]['probability'],drops[0]['source_line']), (1405,2138,100,1037))
        enemy=next(r for r in csv.reader(self.texts['gmsv/data/enemy.txt'].splitlines()) if len(r)>24 and r[3]=='1405')
        self.assertEqual((enemy[14],enemy[24]),('2138','100'))
        self.assertEqual(self.fixture['bosses']['300/sb_skt.arg']['enemies'][3],1405)
        self.assertIn('#define _FIX_ITEMPROB', self.texts['gmsv/include/version.h'])
        self.assertIn('RAND( 0,999)', self.texts['gmsv/char/enemy.c'])
        for path,digest in AUDIT['sources'].items():self.assertEqual(self.spec['sources'][path],digest)

if __name__ == '__main__':
    unittest.main()
