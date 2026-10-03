"""Source-door routes using imported collision, with gated edges explicit.

Ordinary warp cells stop walking expansion (except the arrival cell). This
checks cardinal geometry and source transitions, not battle balance, source
flag acquisition, or rendered pixels. No server or player save is opened.
"""
from collections import deque
import json
from pathlib import Path
import sys

from map_file import load_map
from transmigration_foundation import portals

ROOT=Path(__file__).resolve().parents[1]


def run():
    spec=json.loads((ROOT/'tools/transmigration_foundation_sources.json').read_text())
    fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-foundation.json').read_text())['module']
    edges=portals(ROOT/'references/chenmingbiao-stone-age',[spec['staged_world']])
    # Ambiguous source doors are not selectable alternatives. Reuse an
    # already-reviewed live catalog choice, or exclude the ambiguous cell.
    world=json.loads((ROOT/'client/assets/legacy/world/manifest.json').read_text())
    choices={ (p['from_map'],*p['cell']):(p['to_map'],*p['target'])
              for p in world['portals'] if not p.get('disabled') and not p.get('convenience') }
    for choice in spec['staged_world'].get('portal_choices',[]):
        choices[(choice['from_map'],*choice['cell'])]=(choice['to_map'],*choice['to_cell'])
    destinations={}
    for edge in edges:
        destinations.setdefault((edge['from_map'],*edge['cell']),set()).add((edge['to_map'],*edge['target']))
    edges=[edge for edge in edges if len(destinations[(edge['from_map'],*edge['cell'])])==1
           or choices.get((edge['from_map'],*edge['cell']))==(edge['to_map'],*edge['target'])]
    for npc in fixture['npcs']:
        for branch in npc['branches']:
            if 'Warp' not in branch['actions']:continue
            dest,x,y=map(int,branch['actions']['Warp'].split(','))
            edges.append(dict(from_map=npc['map_id'],cell=npc['cell'],to_map=dest,target=[x,y],source=npc['source_script'],gate=True,condition=branch['condition'],battle=branch['actions'].get('Battle','')))
    maps={}
    by_map={}
    for edge in edges:
        by_map.setdefault(edge['from_map'],[]).append(edge)
    def data(ident):
        if ident not in maps:
            path=ROOT/f'client/assets/legacy/world/{ident}.map'
            if not path.is_file():return None
            maps[ident]=load_map(path)
        return maps[ident]
    def walk(ident,cell):
        m=data(ident)
        if m is None:return set()
        w,h=m['width'],m['height'];x,y=cell
        if not 0<=x<w or not 0<=y<h or m['blocked'][y*w+x]:return set()
        terminals={tuple(e['cell']) for e in by_map.get(ident,[]) if not e.get('gate')}
        seen={tuple(cell)};todo=deque([tuple(cell)])
        while todo:
            x,y=todo.popleft()
            if (x,y) in terminals and [x,y]!=list(cell):continue
            for nx,ny in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
                if 0<=nx<w and 0<=ny<h and not m['blocked'][ny*w+nx] and (nx,ny) not in seen:
                    seen.add((nx,ny));todo.append((nx,ny))
        return seen
    def near(cells,cell,radius):
        x,y=cell
        return any((x+dx,y+dy) in cells for dx in range(-radius,radius+1) for dy in range(-radius,radius+1))
    cases=[('earth',(21001,4,3),(21015,10,8)),('fire',(30001,29,14),(30016,26,30)),
           ('wind',(11201,29,79),(11215,10,10)),('water',(21201,61,46),(21215,25,30)),
           ('water-material',(31301,10,104),(31302,27,31)),('water-sage',(21301,7,3),(21308,20,3))]
    result=[]
    for name,start,goal in cases:
        todo=deque([(start,[])]);visited={start};found=None
        while todo:
            position,route=todo.popleft();ident,x,y=position;cells=walk(ident,[x,y])
            if ident==goal[0] and near(cells,goal[1:],2):found=route;break
            for edge in by_map.get(ident,[]):
                if not near(cells,edge['cell'],2 if edge.get('gate') else 0):continue
                dest=(edge['to_map'],*edge['target'])
                if dest in visited:continue
                visited.add(dest);todo.append((dest,route+[edge]))
        result.append(dict(chain=name,start=list(start),goal=list(goal),reachable=found is not None,route=found or [],visited_arrivals=len(visited)))
    return result


if __name__=='__main__':
    result=run()
    print(json.dumps(result,ensure_ascii=False,indent=2))
    sys.exit(0 if all(r['reachable'] for r in result) else 1)
