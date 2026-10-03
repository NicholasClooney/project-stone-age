"""Wind source binding, rewards, staged-world activation and natural routes."""
from collections import deque
import json
from pathlib import Path
import unittest
from quest_import_common import load_quest_module, merge_quest_module
from map_file import load_map
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'

def routes():
    world=json.loads((ROOT/'client/assets/legacy/world/manifest.json').read_text())
    module=load_quest_module(REF,ROOT/'tools/transmigration_wind_quest_sources.json')
    munde=load_quest_module(REF,ROOT/'tools/munde_cave_quest_sources.json')
    links=[p for p in world['portals'] if not p.get('disabled') and not p.get('convenience')]
    for npc in module['npcs']+munde['npcs']:
        for branch in npc['branches']:
            if 'Warp' not in branch['actions']:continue
            dest,x,y=map(int,branch['actions']['Warp'].split(','))
            links.append(dict(from_map=npc['map_id'],cell=npc['cell'],to_map=dest,target=[x,y],npc_id=npc['id'],source=npc['source_script']))
    occupied={}
    for n in module['npcs']+munde['npcs']:
        if n['source_script']!='100/sb_kbu.arg':occupied.setdefault(n['map_id'],set()).add(tuple(n['cell']))
    maps={};by_map={}
    for p in links:by_map.setdefault(p['from_map'],[]).append(p)
    def walk(ident,cell):
        if ident not in maps:maps[ident]=load_map(ROOT/f'client/assets/legacy/world/{ident}.map')
        m=maps[ident];w,h=m['width'],m['height'];seen={tuple(cell)};todo=deque(seen)
        terminals={tuple(p['cell']) for p in by_map.get(ident,[]) if 'npc_id' not in p}
        while todo:
            x,y=todo.popleft()
            if (x,y) in terminals and (x,y)!=tuple(cell):continue
            for nx,ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                if 0<=nx<w and 0<=ny<h and not m['blocked'][ny*w+nx] and (nx,ny) not in seen and (nx,ny) not in occupied.get(ident,set()):
                    seen.add((nx,ny));todo.append((nx,ny))
        return seen
    result={}
    for name,start,goal in [('wind-up',(11201,29,79),(11215,9,16)),('wind-down',(11215,9,16),(100,278,325)),('munde-up',(11101,33,29),(11107,24,7)),('munde-down',(11107,24,7),(100,466,128))]:
        todo=deque([(start,[])]);seen={start}
        while todo:
            position,path=todo.popleft();ident,x,y=position
            cells=walk(ident,(x,y))
            if ident==goal[0] and goal[1:] in cells:result[name]=path;break
            for p in by_map.get(ident,[]):
                if p['to_map'] not in [100,*range(11101,11108),*range(11201,11216)]:continue
                accessible=tuple(p['cell']) in cells
                if 'npc_id' in p:accessible=any((p['cell'][0]+dx,p['cell'][1]+dy) in cells for dx in range(-2,3) for dy in range(-2,3))
                dest=(p['to_map'],*p['target'])
                if accessible and dest not in seen:seen.add(dest);todo.append((dest,path+[p]))
        if name not in result:raise ValueError('No route '+name)
    return result

class WindChain(unittest.TestCase):
    def test_actual_source_and_shared_order(self):
        wind=load_quest_module(REF,ROOT/'tools/transmigration_wind_quest_sources.json')
        self.assertEqual(len(wind['npcs']),11)
        munde=load_quest_module(REF,ROOT/'tools/munde_cave_quest_sources.json')
        merged=merge_quest_module(munde,wind)
        shared=[n for n in merged['npcs'] if n['source_script']=='sainasu/event/event12']
        self.assertEqual(len(shared),1)
        self.assertEqual([b['source_branch_index'] for b in shared[0]['branches']],[0,1,2,3,4])
        self.assertEqual(set(wind['world']['map_sources']),set(map(str,range(11201,11216))))
        self.assertNotIn('32021',wind['world']['map_sources'])
        guards=[n for n in wind['npcs'] if n['source_script']=='100/sb_kbu.arg']
        self.assertEqual([n['cell'] for n in guards],[[26,40],[42,38]])
        self.assertTrue(all(n['branches'][0]['guard']['cooldown']==180 for n in guards))
    def test_original_reward_icons_and_packs(self):
        from PIL import Image
        from import_legacy import Archive
        import plan_web_packs
        catalog=json.loads((ROOT/'client/assets/legacy/quests/catalog.json').read_text())
        spec=json.loads((ROOT/'tools/transmigration_wind_quest_sources.json').read_text())
        archive=Archive(ROOT/'.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5')
        plan=plan_web_packs.plan()
        for ident in spec['items']:
            with self.subTest(item=ident):
                item=catalog['items'][str(ident)]
                with Image.open(ROOT/'client/assets/legacy'/item['icon_path']) as icon:
                    source=archive.image(int(item['bitmap_id'])).convert('RGBA')
                    self.assertEqual(icon.convert('RGBA').tobytes(),source.tobytes())
                    self.assertEqual(icon.size,source.size)
                self.assertIn(plan_web_packs.RES+item['icon_path'],plan['packs']['core'])
        archive.real.close()
        for ident in range(11201,11216):
            self.assertIn(str(ident),plan['maps'])
    def test_route_fixture(self):
        fixture=json.loads((ROOT/'client/tests/fixtures/transmigration-wind-routes.json').read_text())
        self.assertEqual(routes(),fixture)
        self.assertTrue(any(p.get('source')=='100/sb_kgi.arg' for p in fixture['wind-up']))
        self.assertTrue(any(p.get('source')=='genout/wpm_11206_5_42' for p in fixture['wind-down']))

if __name__=='__main__':
    import sys
    if '--fixture' in sys.argv:(ROOT/'client/tests/fixtures/transmigration-wind-routes.json').write_text(json.dumps(routes(),ensure_ascii=False,indent=2)+'\n')
    else:unittest.main()
