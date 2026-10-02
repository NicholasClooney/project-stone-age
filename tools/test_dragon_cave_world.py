"""Original entrance/stairs and seventh-floor component gate, no y heuristic."""
import json
from collections import deque
from pathlib import Path
import unittest
from map_file import load_map
ROOT=Path(__file__).resolve().parents[1]/'client/assets/legacy/world'
def component(floor,start):
 d=load_map(ROOT/f'{floor}.map');w=d['width'];h=d['height'];q=deque([tuple(start)]);seen={tuple(start)}
 while q:
  x,y=q.popleft()
  for nx,ny in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
   if 0<=nx<w and 0<=ny<h and not d['blocked'][ny*w+nx] and (nx,ny) not in seen:seen.add((nx,ny));q.append((nx,ny))
 return seen
class DragonWorldTests(unittest.TestCase):
 def test_source_route_and_gate(self):
  world=json.loads((ROOT/'manifest.json').read_text());links=[p for p in world['portals'] if not p.get('disabled')]
  entry=next(p for p in links if p['from_map']==200 and p['cell']==[433,742] and p['to_map']==20801);arrival=entry['target']
  for floor in range(20801,20807):
   seen=component(floor,arrival)
   if floor==20801:self.assertTrue(any(c in seen for c in [(12,63),(14,63),(13,62),(13,64)]))
   door=next(p for p in links if p['from_map']==floor and p['to_map']==floor+1)
   self.assertIn(tuple(door['cell']),seen);arrival=door['target']
  entrance=component(20807,arrival);reward=component(20807,[13,35])
  self.assertIn((11,38),entrance);self.assertFalse(entrance&reward)
  for point in [(7,9),(23,7),(41,15)]:self.assertIn(point,reward)
  self.assertTrue(any(y>=38 for x,y in reward),'reward component extends south: no y cutoff')
  self.assertFalse(any(p['from_map']==20807 and tuple(p['cell']) in entrance and p['to_map']==20807 and tuple(p['target']) in reward for p in links),'no unconditional portal bypasses source gate')
if __name__=='__main__':unittest.main()
