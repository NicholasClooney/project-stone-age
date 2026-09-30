"""Check reviewed local imports against walking components and web packs."""
import argparse
from array import array
from collections import defaultdict, deque
import json
from pathlib import Path
from import_world import REGION_REVIEWS, reachable_cells
from map_file import load_map


def verify(region=None):
    root=Path('client/assets/legacy')
    manifest=json.loads((root/'world/manifest.json').read_text())
    reviews={region:REGION_REVIEWS[region]} if region else REGION_REVIEWS
    wanted={i for review in reviews.values() for i in review['maps']}
    info=manifest['maps']
    data={}
    labels={}
    nodes=[]
    def component(ident,cell):
        if ident not in data:
            data[ident]=load_map(root/info[str(ident)]['path'])
            labels[ident]=array('i',[-1])*(data[ident]['width']*data[ident]['height'])
        d=data[ident]
        x,y=cell
        assert 0<=x<d['width'] and 0<=y<d['height'],(ident,cell,'outside')
        index=y*d['width']+x
        assert not d['blocked'][index],(ident,cell,'blocked active endpoint')
        if labels[ident][index]<0:
            seen=reachable_cells(d,cell)
            key=len(nodes)
            nodes.append((ident,index))
            for i,v in enumerate(seen):
                if v:labels[ident][i]=key
        return labels[ident][index]
    edges,reverse=defaultdict(set),defaultdict(set)
    for p in manifest['portals']:
        if p.get('disabled'):continue
        a,b=component(p['from_map'],p['cell']),component(p['to_map'],p['target'])
        edges[a].add(b)
        reverse[b].add(a)
    starts={component(i,info[str(i)]['spawn']) for i in [100,200,300,400] if str(i) in info}
    def walk(graph):
        seen=set(starts);todo=deque(starts)
        while todo:
            for node in graph[todo.popleft()]-seen:
                seen.add(node);todo.append(node)
        return seen
    forward,backward=walk(edges),walk(reverse)
    areas=json.loads((root/'encounters/catalog.json').read_text())['areas']
    encounters={int(a['map_id']) for a in areas}
    active_encounters={int(a['map_id']) for a in areas if int(a.get('probability_max',0))>0 and a.get('groups',[])}
    plan=json.loads(Path('build/web-packs/plan.json').read_text())
    rows=[]
    for ident in sorted(wanted & set(map(int,info))):
        metadata=info[str(ident)];report=manifest['provenance']['maps'][str(ident)]
        assert not report['missing_graphics'],(ident,'missing graphics')
        spawn=component(ident,metadata['spawn'])
        assert spawn in forward and spawn in backward,(ident,'spawn disconnected from island or return')
        assert not {n for n in forward-backward if nodes[n][0]==ident},(ident,'arrival component has no return')
        assert 'res://assets/legacy/'+metadata['path'] in plan['packs']['map-'+str(ident)],(ident,'missing own web pack')
        gates=sorted({p['gate_source'] for p in manifest['portals'] if p.get('gate_source') and not p.get('disabled') and ident in (p['from_map'],p['to_map'])})
        rows.append(dict(map_id=ident,name=metadata['name'],encounter_area=ident in encounters,encounters=ident in active_encounters,gates=gates,kind=metadata['kind']))
    result=dict(maps=rows,skipped=sorted(wanted-set(map(int,info))))
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region',choices=sorted(REGION_REVIEWS))
    verify(parser.parse_args().region)
