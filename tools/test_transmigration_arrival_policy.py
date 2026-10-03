"""Independent original portal oracle for arrival tests, not a grant fixture."""
import hashlib
import json
import unittest
from collections import deque
from pathlib import Path
from map_file import load_map

ROOT = Path(__file__).resolve().parents[1]

class ArrivalSource(unittest.TestCase):
    def test_complete_original_portal_set(self):
        data = json.loads((ROOT/'client/tests/fixtures/transmigration-arrival-portals.json').read_text())
        raw = (ROOT/'references/chenmingbiao-stone-age'/data['source']).read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), data['sha256'])
        expected = []
        for line, text in enumerate(raw.decode('gb18030').splitlines(), 1):
            fields = text.split(':')
            if len(fields) < 5:
                continue
            try:
                a = list(map(int, fields[2].split(',')))
                b = list(map(int, fields[3].split(',')))
            except ValueError:
                continue
            if len(a) != 3 or len(b) != 3:
                continue
            if a[0] in range(32001,32022) or b[0] in range(32001,32022) or a == [300,104,228]:
                expected.append(dict(from_map=a[0], cell=a[1:], to_map=b[0], target=b[1:], source_line=line))
        self.assertEqual(sorted(expected,key=lambda p:p['source_line']), sorted(data['portals'],key=lambda p:p['source_line']))
        self.assertFalse(any(p['from_map'] not in range(32001,32022) and p['to_map'] in range(32001,32022) for p in expected))
        self.assertFalse(any(p['from_map'] in range(32001,32011) and p['to_map'] in range(32011,32022) for p in expected))
        self.assertFalse(any(p['from_map'] != 32021 and p['to_map'] == 32021 for p in expected))

    def test_prison_oracle_keeps_all_eighteen_reviewed_endpoints(self):
        fixture = json.loads((ROOT/'client/tests/fixtures/prison-arrival-portals.json').read_text())
        review = json.loads((ROOT/'tools/prison_world_sources.json').read_text())
        self.assertEqual(fixture['portals'], review['ordinary_portals'])
        self.assertEqual(fixture['source_sha'], review['portal_sources'])
        self.assertEqual(len(fixture['portals']),18)
        for source, digest in fixture['source_sha'].items():
            self.assertEqual(hashlib.sha256((ROOT/'references/chenmingbiao-stone-age'/source).read_bytes()).hexdigest(),digest)

    def test_public_pocket_is_complete_original_component(self):
        data = json.loads((ROOT/'client/tests/fixtures/transmigration-arrival-portals.json').read_text())
        m = load_map(ROOT/'client/assets/legacy/world/300.map')
        floor = {(x,y) for x,y,_ in m['ground'] if not m['blocked'][y*m['width']+x]}
        blocked = {(103,228),(108,225),(104,228)}
        start = (105,228)
        seen = {start}
        queue = deque([start])
        while queue:
            x,y = queue.popleft()
            for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if p in floor and p not in blocked and p not in seen:
                    seen.add(p)
                    queue.append(p)
        self.assertEqual(sorted(seen), sorted(map(tuple,data['entry_pocket'])))
        policy = (ROOT/'client/server/quest_arrival_policy.gd').read_text()
        body = policy.split('static func approach_cell(',1)[1].split('static func ',1)[0]
        cells = json.loads(body.split('and [cell.x,cell.y] in ',1)[1].strip())
        self.assertEqual(sorted(seen), sorted(map(tuple,cells)))
        self.assertEqual(len(seen),12)
        self.assertIn((108,226),seen)
        self.assertNotIn((102,228),seen)

if __name__ == '__main__':
    unittest.main()
