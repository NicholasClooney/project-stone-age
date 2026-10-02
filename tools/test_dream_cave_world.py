"""Actual dream maze paths end at the guard, never in its reward component."""
import json
from collections import deque
from pathlib import Path
import unittest
from map_file import load_map
ROOT=Path(__file__).resolve().parents[1]/'client/assets/legacy/world'
def labels(map_id):
 d=load_map(ROOT/f'{map_id}.map');w=d['width'];h=d['height'];result={};serial=0
 for y in range(h):
  for x in range(w):
   if (x,y) in result or d['blocked'][y*w+x] or (x,y) in [(33,41),(34,41),(34,25)]:continue
   serial+=1;q=deque([(x,y)]);result[x,y]=serial
   while q:
    xx,yy=q.popleft()
    for nx,ny in [(xx+1,yy),(xx-1,yy),(xx,yy+1),(xx,yy-1)]:
     if 0<=nx<w and 0<=ny<h and not d['blocked'][ny*w+nx] and (nx,ny) not in result and (nx,ny) not in [(33,41),(34,41),(34,25)]:result[nx,ny]=serial;q.append((nx,ny))
 return result
class DreamWorld(unittest.TestCase):
 def test_original_maze_and_time_records(self):
  w=json.loads((ROOT/'manifest.json').read_text());links=[p for p in w['portals'] if not p.get('disabled')]
  time=[p for p in links if p.get('requires_time')]
  self.assertEqual({(p['from_map'],tuple(p['cell']),p['to_map'],p['requires_time']) for p in time},{(400,(97,119),41,'A'),(400,(98,119),41,'M'),(400,(97,120),41,'M'),(400,(96,119),41,'M'),(400,(87,101),42,'N')})
  for map_id in [41,42]:
   rooms=labels(map_id);start=rooms[11,8];guard=rooms[34,42];reward=rooms[34,39];self.assertNotEqual(guard,reward)
   seen={start};q=deque([start])
   while q:
    room=q.popleft()
    for p in links:
     if p['from_map']!=map_id or p['to_map']!=map_id or rooms.get(tuple(p['cell']))!=room:continue
     target=rooms[tuple(p['target'])]
     if target not in seen:seen.add(target);q.append(target)
   self.assertIn(guard,seen);self.assertNotIn(reward,seen,'source maze cannot skip final battle wall')
  selected=[p for p in links if p['from_map']==42 and p['cell']==[45,59]]
  self.assertEqual([p['target'] for p in selected],[[31,44]])
if __name__=='__main__':unittest.main()
