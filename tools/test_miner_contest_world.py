"""Imported original mine route and non-bypassable sixth-floor ticket gate."""
import json
from collections import deque
from pathlib import Path
import unittest
from map_file import load_map
ROOT=Path(__file__).resolve().parents[1]/'client/assets/legacy/world'
class MinerWorldTests(unittest.TestCase):
 def test_natural_stairs_and_original_npc_access(self):
  world=json.loads((ROOT/'manifest.json').read_text())
  links=[p for p in world['portals'] if not p.get('disabled')]
  entry=next(p for p in links if p['from_map']==300 and p['cell']==[483,196] and p['to_map']==31801)
  self.assertEqual(entry['target'],[37,49])
  arrival=entry['target']
  for floor in range(31801,31806):
   data=load_map(ROOT/f'{floor}.map');w=data['width'];h=data['height']
   queue=deque([tuple(arrival)]);seen={tuple(arrival)}
   while queue:
    x,y=queue.popleft()
    for nx,ny in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
     if 0<=nx<w and 0<=ny<h and not data['blocked'][ny*w+nx] and (nx,ny) not in seen:
      seen.add((nx,ny));queue.append((nx,ny))
   if floor<31805:
    door=next(p for p in links if p['from_map']==floor and p['to_map']==floor+1)
    self.assertIn(tuple(door['cell']),seen);arrival=door['target']
   else:
    for x,y in [(19,21),(33,23),(26,23),(22,4)]:
     self.assertTrue(any((x+dx,y+dy) in seen for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]),f'NPC {x},{y} reachable from natural stairs')
  self.assertFalse(any(p['to_map']==31806 for p in links),'floor6 has no unconditional forward portal')
  self.assertTrue(any(p['from_map']==31806 and p['to_map']==31805 and p['cell']==[34,5] for p in links))
if __name__=='__main__':unittest.main()
