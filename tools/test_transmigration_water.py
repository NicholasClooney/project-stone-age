"""Water46 source oracle: full weighted rewards and every activated drop slot."""
import copy,json,csv,re,unittest,tempfile
from pathlib import Path
from quest_import_common import load_quest_module,registered_quest_modules
from import_encounters import drop_slots
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
SPEC=ROOT/'tools/transmigration_water_quest_sources.json'
class WaterTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.spec=json.loads(SPEC.read_text());cls.module=load_quest_module(REF,SPEC)
 def npc(self,name):return next(n for n in self.module['npcs'] if n['source_script']=='jaruga/event/'+name)
 def test_exact_enable_disable_descriptor(self):
  descriptor=json.loads((ROOT/"client/data/quests/transmigration-water.json").read_text())
  self.assertEqual(descriptor["enabled_events"],[46])
  for events in [[],[46]]:
   entry=dict(descriptor,enabled_events=events)
   with tempfile.NamedTemporaryFile(mode="w+",suffix=".json") as f:
    json.dump(dict(version=1,modules=[entry]),f);f.flush()
    modules=list(registered_quest_modules(REF,f.name))
   self.assertEqual(len(modules),1);self.assertEqual(modules[0]["enabled_events"],events)
   self.assertEqual(len(modules[0]["npcs"]),15)
 def test_acceptance_is_any_previous_spirit(self):
  self.assertEqual([b['condition'] for b in self.npc('hekisei')['branches'][:3]],['LV>64&ENDEV=4&ENDEV='+str(e) for e in [39,40,42]])
 def test_original_or_and_bare_material_consumption(self):
  b=self.npc('hekisei03')['branches'][1]
  self.assertEqual(b['condition'],'LV>64&NOWEV=46&ITEM=2767&ITEM=2768,LV>64&NOWEV=46&ITEM!=2769')
  self.assertEqual(b['actions'],{'DelItem':'2767,2768','GetItem':'2769'})
 def test_complete_boxes_and_source_binding(self):
  for name,cell,first in [('hekisei05',[23,34],75),('hekisei06',[21,34],74)]:
   npc=self.npc(name);b=npc['branches'][0]
   self.assertEqual((npc['map_id'],npc['cell']),(21215,cell))
   raw=(REF/'gmsv/data/npc/jaruga/event'/name).read_text(encoding='gb18030')
   pool=list(map(int,b['actions']['GetRandItem'].split(',')))
   self.assertEqual(pool,list(map(int,re.search(r'GetRandItem:([^\n]+)',raw)[1].split(','))))
   self.assertEqual(len(pool),36);self.assertEqual(len(set(pool)),24);self.assertEqual(pool.count(first),2)
   self.assertEqual(b['condition'],'LV>0&ITEM=2766');self.assertEqual(b['actions']['DelItem'],'2766');self.assertTrue(b['source_break'])
 def test_all_static_drop_slots(self):
  entries=self.module['drops'];self.assertEqual(len(entries),13)
  for enemy in [1324,1334,1335,1336,1347,1348,1349]:
   rows=[d for d in entries if d['enemy_id']==enemy]
   self.assertTrue(rows)
   expected=drop_slots(rows[0]['source_raw_columns'])
   self.assertEqual([(d['item_id'],d['probability']) for d in rows],[(d['item_id'],d['probability']) for d in expected])
  bad=copy.deepcopy(self.spec);bad['drops']=[d for d in bad['drops'] if d['item_id']!=1249]
  with self.assertRaises(ValueError):load_quest_module(REF,bad)
 def test_guards_and_unimplemented_effects(self):
  guards=[n for n in self.module['npcs'] if n['source_script'].startswith('200/sb_mz')]
  self.assertEqual(len(guards),2)
  for n in guards:self.assertEqual(len(n['branches'][0]['guard']['enemy_ids']),10)
  for item in self.module['items'].values():
   self.assertTrue(all(not e['active'] for e in item['effects']))
 def test_original_free_lake_entry_source_evidence(self):
  rows=(REF/'gmsv/data/map/mapwarp.txt').read_text(encoding='gb18030').splitlines()
  self.assertEqual(rows[2738:2743],[
   'NONE:NULL:5000,46,18:31301,10,10:NULL',
   'NONE:NULL:31301,10,10:5000,46,18:NULL',
   'NONE:NULL:31301,10,103:40,12,1:NULL',
   'NONE:NULL:31301,9,51:31302,52,11:NULL',
   'NONE:NULL:31302,52,11:31301,9,51:NULL'])
  rows=(REF/'gmsv/data/npc/genout/dungeon03.create').read_text(encoding='gb18030').splitlines()
  for start,origin,cell,destination in [(61,5000,'46,18','31301|10|10'),(70,31301,'10,10','5000|46|18'),(88,31301,'9,51','31302|52|11'),(97,31302,'52,11','31301|9|51')]:
   self.assertEqual(rows[start:start+7],[f'floorid={origin}',f'borncorner={cell},{cell}','time=0','ignoreinvincible=1','createnum=1',f'enemy=npcgen_warp|{destination}','}'])
 def test_world_only_water_maps(self):
  self.assertEqual(set(map(int,self.spec['world']['map_sources'])),set(range(21201,21216))|set(range(21301,21316))|{31301,31302}|set(range(30301,30308)))
  self.assertNotIn('32021',self.spec['world']['map_sources'])
if __name__=='__main__':unittest.main()
