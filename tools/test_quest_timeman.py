import copy
import hashlib
import json
from pathlib import Path
import unittest
from test_quest_import_common import gold_bui_manifest,REFERENCE
from quest_timeman import BINDINGS
from quest_import_common import load_quest_module
ROOT=Path(__file__).resolve().parents[1]
def manifest():
 spec=gold_bui_manifest();spec.update(id='dream-timeman-fixture',scripts={},items=[],reward_enemies=[],handlers={s:{'kind':'timeman','events':[34]} for s in BINDINGS})
 spec['creates']=['gmsv/data/npc/genout/mugendungeon.create','gmsv/data/npc/genout/mugendungeon2.create']
 paths=spec['creates']+['gmsv/data/npc/'+s for s in BINDINGS]+['gmsv/npc/npc_timeman.c','gmsv/handletime.c','gmsv/include/handletime.h','gmsv/data/npc/genout/npcgen.template']
 spec['sources'].update({p:hashlib.sha256((REFERENCE/p).read_bytes()).hexdigest() for p in paths})
 return spec
class TimeManTests(unittest.TestCase):
 def test_actual_bound_four_instances(self):
  spec=manifest();module=load_quest_module(REFERENCE,spec)
  fixture=json.loads((ROOT/'client/tests/fixtures/dream-timeman.json').read_text())
  self.assertEqual(module,fixture['module'])
  self.assertEqual(len(module['npcs']),4)
  for npc in module['npcs']:
   cell,graphic,alternate=BINDINGS[npc['source_script']]
   self.assertEqual((npc['cell'],npc['graphic'],npc['time_visuals']['changed']['graphic']),(cell,graphic,alternate))
   self.assertEqual(npc['handler'],'TimeMan')
   self.assertFalse(npc['branches'])
 def test_both_original_graphics_export_and_belong_to_map_pack(self):
  import tempfile
  from unittest.mock import patch
  from PIL import Image
  import plan_web_packs
  from import_early_quests import Archive,prepare_npc_art,write_npc_art
  npcs=load_quest_module(REFERENCE,manifest())['npcs']
  archive=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')
  art=prepare_npc_art(archive,npcs)
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);write_npc_art(archive,art,root)
   for npc in npcs:
    for mode in ['main','changed']:
     visual=npc['time_visuals'][mode]
     expected=archive.image(visual['bitmap_id']).convert('RGBA')
     with Image.open(root/visual['path']) as image:actual=image.convert('RGBA')
     self.assertEqual(actual.size,expected.size)
     self.assertEqual(actual.tobytes(),expected.tobytes())
     entry=archive.entries[visual['bitmap_id']]
     self.assertEqual(visual['offset'],[entry['x'],entry['y']])
   files={'world/manifest.json':{'maps':{'400':{'path':'world/400.json'}}},'world/400.json':{'images':{}},'characters/catalog.json':{},'battle/manifest.json':{},'quests/catalog.json':{'npcs':npcs}}
   for path,data in files.items():
    target=root/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(data))
   with patch.object(plan_web_packs,'LEGACY',root):plan=plan_web_packs.plan()
   for npc in npcs:
    for mode in ['main','changed']:
     path=plan_web_packs.RES+npc['time_visuals'][mode]['path']
     self.assertIn(path,plan['packs']['map-400'])
     self.assertNotIn(path,plan['packs'].get('core',[]))

 def test_unreviewed_template_and_source_fail(self):
  for path in ['gmsv/npc/npc_timeman.c','gmsv/data/npc/genout/npcgen.template']:
   spec=manifest();spec['sources'].pop(path)
   with self.assertRaises(ValueError):load_quest_module(REFERENCE,spec)
  from quest_timeman import visuals
  spec=manifest();texts={p:(REFERENCE/p).read_text(encoding='gb18030') for p in spec['sources']}
  script=next(iter(BINDINGS));fields={'floorid':'400','borncorner':'95,120,95,120','graphicname':'16203','dir':'6'}
  for old,new in [('time:AFTER','time:ALLNOON'),('change_no:16200','change_no:9999')]:
   bad=dict(texts);key='gmsv/data/npc/'+script;bad[key]=bad[key].replace(old,new)
   with self.assertRaises(ValueError):visuals(script,fields,bad)
if __name__=='__main__':unittest.main()
