"""Quest 44 real-source boundaries, distinct route instances and private answers."""
import copy
import json
from pathlib import Path
import unittest
import import_golden_bui as gold

REFERENCE=Path(__file__).resolve().parents[1]/'references/chenmingbiao-stone-age'


class GoldenBuiImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec=json.loads(gold.SPEC.read_text())
        cls.data=gold.build_sidecar(REFERENCE)

    def test_complete_builder_static_fees_rewards_and_instances(self):
        data=gold.build(REFERENCE)
        self.assertEqual(len(data["npcs"]),78)
        self.assertEqual(data["reward_pets"]["14"]["template_id"],12)
        for room in [810,850]:
            self.assertIn(f"quiz/equiz_02@{room}:28:16",[n["id"] for n in data["npcs"]])
        fees={b["actions"]["DelStone"] for n in data["npcs"] for b in n.get("branches",[]) if "DelStone" in b["actions"]}
        self.assertEqual(fees,{"LV*20","LV*40"})
        self.assertEqual({n["map_id"] for n in data["npcs"] if n.get("source_script")=="quiz/equiz_02"},{810,850})

    def test_three_full_original_routes(self):
        for base in (800,820,840):
            route=[n for n in self.data['npcs'] if base<=n['map_id']<base+10]
            self.assertEqual(sum(n['kind']=='golden_bui_quiz' for n in route),7)
            self.assertEqual(sum(n['kind']=='golden_bui_janken' for n in route),3)
            counts=[self.data['services'][n['service_id']]['count'] for n in route if n['kind']=='golden_bui_quiz']
            self.assertEqual(counts,[1,2,3,5,5,7,10])
        self.assertNotIn('812',self.data['world']['map_sources'])
        self.assertTrue(all(n['events']==[44] for n in self.data['npcs']))

    def test_public_npcs_have_no_answers(self):
        for n in self.data['npcs']:
            self.assertNotIn('questions',n)
            self.assertNotIn('service',n)
            self.assertNotIn('answer',json.dumps(n))
            self.assertIn(n['service_id'],self.data['services'])

    def test_real_question_bitmask_and_no_missing_fields(self):
        rule=self.data['services']['genout/quz_800_29_19']
        self.assertEqual(rule['level_mask'],16)
        self.assertTrue(all(gold.eligible(q,rule) for q in rule['questions']))
        self.assertIn(11,[q['id'] for q in rule['questions']])
        self.assertNotIn(8,[q['id'] for r in self.data['services'].values() for q in r.get('questions',[])])

    def test_source_order_portal_collisions_are_explicit(self):
        conflicts=self.data['portal_conflicts']
        self.assertEqual(len(conflicts),4)
        for cell in ([28,27],[29,27]):
            match=next(x for x in conflicts if x['selected']['from_map']==810 and x['selected']['cell']==cell)
            self.assertEqual(match['selected']['to_map'],809)
            self.assertEqual(match['ignored']['to_map'],829)
            self.assertLess(match['selected']['source_create_index'],match['ignored']['source_create_index'])

    def test_random_disciple_drop_whitelist(self):
        drops=self.data['drops']
        self.assertEqual(len(drops),18)
        self.assertEqual({d['enemy_id'] for d in drops},set(range(1287,1305)))
        for d in drops:
            self.assertEqual(d['probability'],600)
            self.assertEqual(d['item_id'],2752 if (d['enemy_id']-1287)%2==0 else 2751)
            self.assertEqual(d['source_line'],919+d['enemy_id']-1287)
        rows=[]
        for f in ['group.txt','group1.txt']:
            lines=(REFERENCE/'gmsv/data'/f).read_bytes().splitlines()
            rows.append(lines[584:587])
        self.assertEqual(*rows)

    def test_sha_and_explicit_binding_fail_closed(self):
        altered=copy.deepcopy(self.spec)
        altered['sources']['gmsv/data/question.txt']='0'*64
        with self.assertRaisesRegex(ValueError,'Unreviewed'):gold.build_sidecar(REFERENCE,altered)
        altered=copy.deepcopy(self.spec)
        altered['sidecar_scripts']['genout/quz_812_28_14']='quiz'
        with self.assertRaises((KeyError,ValueError)):gold.build_sidecar(REFERENCE,altered)


if __name__=='__main__':unittest.main()
