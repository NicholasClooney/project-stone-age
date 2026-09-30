"""Verify local scenic imports, component travel, encounters and web packs.

Requires ignored original assets; does not change them or contact the game.
"""
import json
from collections import defaultdict, deque
from pathlib import Path
from import_world import JYARUGA_SCENIC_MAPS, reachable_cells
from map_file import load_map


def verify(root=Path('client/assets/legacy'), plan_path=Path('build/web-packs/plan.json')):
    manifest = json.loads((root/'world/manifest.json').read_text())
    ids = JYARUGA_SCENIC_MAPS & set(map(int, manifest['maps']))
    data = {i: load_map(root/manifest['maps'][str(i)]['path']) for i in ids | {200}}
    components = {}
    def component(ident, cell):
        d = data[ident]
        index = cell[1]*d['width']+cell[0]
        assert not d['blocked'][index], (ident, cell, 'blocked endpoint')
        lookup = components.setdefault(ident, {})
        if index not in lookup:
            cells = reachable_cells(d, cell)
            key = (ident, next(i for i,v in enumerate(cells) if v))
            lookup.update((i,key) for i,v in enumerate(cells) if v)
        return lookup[index]
    graph, reverse = defaultdict(set), defaultdict(set)
    for p in manifest['portals']:
        if p.get('disabled') or p['from_map'] not in data or p['to_map'] not in data:
            continue
        a,b = component(p['from_map'],p['cell']), component(p['to_map'],p['target'])
        graph[a].add(b)
        reverse[b].add(a)
    def walk(edges, start):
        seen = {start}
        todo = deque([start])
        while todo:
            for node in edges[todo.popleft()]-seen:
                seen.add(node)
                todo.append(node)
        return seen
    start = component(200,manifest['maps']['200']['spawn'])
    forward, backward = walk(graph,start), walk(reverse,start)
    assert not {node for node in forward-backward if node[0] in ids}, 'Scenic arrival component cannot return to island'
    encounters = {int(a['map_id']) for a in json.loads((root/'encounters/catalog.json').read_text())['areas']}
    plan = json.loads(plan_path.read_text())
    result = []
    for ident in sorted(ids):
        info = manifest['maps'][str(ident)]
        assert not manifest['provenance']['maps'][str(ident)]['missing_graphics'], ident
        spawn = component(ident,info['spawn'])
        assert spawn in forward, (ident,'cannot enter from island')
        assert spawn in backward, (ident,'cannot return to island')
        assert ident in encounters, (ident,'missing original encounters')
        assert info['kind'] == 'dungeon', ident
        assert f'res://assets/legacy/{info["path"]}' in plan['packs'][f'map-{ident}'], ident
        gates = [p['gate_source'] for p in manifest['portals'] if p.get('gate_source') and (p['from_map']==ident or p['to_map']==ident)]
        result.append(dict(map_id=ident,name=info['name'],encounters=ident in encounters,gates=gates))
    print(json.dumps(dict(maps=result,skipped=sorted(JYARUGA_SCENIC_MAPS-ids)),ensure_ascii=False,indent=2))
    return result


if __name__ == '__main__':
    verify()
