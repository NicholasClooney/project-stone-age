"""Independent fixed source oracle for the exact approved equipment set."""
import csv,hashlib,json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXPECTED=[33,36,45,46,60,65,74,75,77,78,157,160,162,165,168,170,184,185,192,193,240,244,250,251,255,256,257,261,266,282,283,287,288,339,340,344,345,356,359,364,378,379,383,384,440,442,443,453,457,458,459,477,478,485,486,530,532,540,542,544,558,561,562,578,579,584,585,645,646,652,655,664,667,676,677,681,682,743,745,747,750,751,755,758,773,774,782,783,874,875,877,878,957,964,966,970,971,975,976,982,983,1034,1036,1044,1045,1047,1056,1064,1065,1069,1070,1141,1144,1154,1156,1159,1165,1168,1169,1172,1173,1269,1352,1358,1359,1367,1451,1460,1466,2691,2692,2693,2694,2695,2696,2699,2700,2701,2706,2707,2766,2770]
class EquipmentSource(unittest.TestCase):
 def test_exact_source_fields_and_migration(self):
  fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-equipment.json').read_text())
  self.assertEqual(fixture['ids'],EXPECTED);self.assertEqual(len(EXPECTED),142)
  raw=(ROOT/'references/chenmingbiao-stone-age'/fixture['source']).read_bytes()
  self.assertEqual(hashlib.sha256(raw).hexdigest(),fixture['sha256'])
  rows={int(r[16]):(i,r) for i,r in enumerate(csv.reader(raw.decode('gb18030').splitlines()),1) if len(r)>75 and r[16].isdigit()}
  code=(ROOT/'client/server/original_equipment.gd').read_text()
  definitions={int(k):json.loads(v) for k,v in re.findall(r'^\s*(\d+):(\{[^\n]+?\}),',code,re.M)}
  for item in fixture['records']:
   i=item['id'];line,r=rows[i];d=definitions[i]
   with self.subTest(item=i):
    self.assertEqual(item['item']['raw_columns'],r);self.assertEqual(item['item']['source_line'],line)
    self.assertEqual(d,item['definition']);self.assertEqual(d['name'],r[0]);self.assertEqual(d['level'],int(r[22] or 0));self.assertEqual(d['durability'],int(r[30] or 0));self.assertEqual(r[30],r[31])
    t=int(r[19]);slot='arm' if t in [0,1,2,3,4,5,17,18,19] else {6:'head',7:'body',8:'bracelet'}.get(t,'amulet')
    self.assertEqual(d['type'],t);self.assertEqual(d['slot'],slot)
    for stat,col in [('attack',37),('defence',39),('speed',41),('charm',49)]:self.assertEqual(r[col],r[col+1]);self.assertEqual(d[stat],int(r[col] or 0))
  migrated=json.loads(re.search(r'const NEWLY_WEARABLE := (\[[\s\S]*?\])',code)[1])
  old=[1357,2460,2487,2489,2491,2492,2493,2494,2505,2605,2606]
  expected_positive=[i for i in EXPECTED if definitions[i]['durability']>0]
  self.assertEqual(migrated,old+expected_positive);self.assertEqual(fixture['positive_durability_ids'],expected_positive)
  self.assertNotIn(1052,migrated)
if __name__=='__main__':unittest.main()
