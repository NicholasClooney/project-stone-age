"""Read-only original dream source audit; does not enable unresolved branches."""
import hashlib,json,csv
from pathlib import Path
import unittest
from import_early_quests import parse_script
from quest_source_handlers import fixed_enemy_audit
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'
SPEC=ROOT/'tools/dream_cave_quest_sources.json'
class DreamSourceAudit(unittest.TestCase):
 def test_pinned_three_round_order(self):
  spec=json.loads(SPEC.read_text())
  for path,sha in spec['sources'].items():self.assertEqual(hashlib.sha256((REF/path).read_bytes()).hexdigest(),sha)
  def script(name,branches):return parse_script((REF/f'gmsv/data/npc/seimu/event/{name}').read_bytes().decode('gb18030'),branches)
  # Strict parser returns default text and exact selected source branches.
  _,request=script('event01_1',[0,1,2]);_,reward=script('event01_2',[1,2,3])
  self.assertEqual([b['event'] for b in reward],[34,33,32])
  self.assertEqual([b['actions']['EndSetFlg'] for b in reward],['34','33','32'])
  self.assertEqual([b['actions']['GetItem'] for b in reward],['2604','2605','2606'])
  self.assertEqual([b['condition'] for b in request],['ENDEV=4&ENDEV=33&ENDEV=32','ENDEV=4&ENDEV=32','ENDEV=4'])
 def test_equipment_source_fields(self):
  rows={r[16]:r for r in csv.reader((REF/'gmsv/data/itemset.txt').read_bytes().decode('gb18030').splitlines()) if len(r)>78}
  self.assertEqual(rows['2605'][19:23],['6','0','0','35'])
  self.assertEqual(rows['2606'][19:23],['9','0','0','35'])
  self.assertEqual(rows['2605'][37:43],['0','0','4','4','2','2'])
  self.assertEqual(rows['2606'][37:43],['2','2','0','0','1','1'])
  self.assertEqual(rows['2606'][49:51],['5','5'])
  for id in ['2605','2606']:self.assertEqual(rows[id][30:32],['2500000','2500000'])
 def test_ten_enemy_source_not_two_visible_npcs(self):
  texts={p:(REF/p).read_bytes().decode('gb18030') for p in ['gmsv/data/enemy.txt','gmsv/data/enemybase.txt']}
  expected=[1095,1095,1095,1087,1086,1096,1096,1096,1096,1096]
  for i,x in [(1,34),(2,33)]:
   fields=dict(line.split(':',1) for line in (REF/f'gmsv/data/npc/400/sb_muge{i}.arg').read_bytes().decode('gb18030').splitlines() if ':' in line)
   self.assertEqual([int(n) for n in fields['enemyno'].split(',')],expected)
   self.assertEqual([int(fields[k]) for k in ['warpfl','warpx','warpy']],[41,x,39])
  audit=fixed_enemy_audit(REF,texts,expected)
  self.assertEqual(set(audit['enemies']),{'1095','1087','1086','1096'})
  self.assertTrue(all(len(b['skills'])==7 for b in audit['bases'].values()))
if __name__=='__main__':unittest.main()
