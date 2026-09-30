"""Walking-component graph of original map cells, including same-map doors."""
from array import array
from collections import defaultdict, deque
from pathlib import Path
from map_file import load_map


class WorldComponents:
    def __init__(self, root, maps, portals, flood):
        self.root=Path(root);self.maps=maps;self.flood=flood
        self.data={};self.labels={};self.nodes=[]
        self.edges=defaultdict(set);self.reverse=defaultdict(set)
        for p in portals:
            if p.get('disabled'):continue
            a,b=self.component(p['from_map'],p['cell']),self.component(p['to_map'],p['target'])
            self.edges[a].add(b);self.reverse[b].add(a)
        self.starts={self.component(i,maps[str(i)]['spawn']) for i in (100,200,300,400) if str(i) in maps}
        self.forward=self.walk(self.edges);self.backward=self.walk(self.reverse)

    def component(self, ident, cell):
        if ident not in self.data:
            d=load_map(self.root/self.maps[str(ident)]['path']);self.data[ident]=d
            self.labels[ident]=array('i',[-1])*(d['width']*d['height'])
        d=self.data[ident];x,y=cell
        if not (0<=x<d['width'] and 0<=y<d['height']) or d['blocked'][y*d['width']+x]:
            raise ValueError(f'Active portal/spawn blocked or outside map: {ident} {cell}')
        index=y*d['width']+x
        if self.labels[ident][index]<0:
            seen=self.flood(d,cell);key=len(self.nodes);self.nodes.append((ident,index))
            for i,v in enumerate(seen):
                if v:self.labels[ident][i]=key
        return self.labels[ident][index]

    def walk(self, graph):
        seen=set(self.starts);todo=deque(self.starts)
        while todo:
            for node in graph[todo.popleft()]-seen:
                seen.add(node);todo.append(node)
        return seen


def finalize_reviewed_maps(root, metadata, portals, residents, reports, reviewed, flood, safe_spawn):
    graph=WorldComponents(root,metadata,portals,flood)
    # A source door may rely on a quest script that is not restored. Keep its
    # original record but close an arrival that cannot return, rather than
    # inventing a reverse warp or trapping scenery visitors.
    for p in portals:
        if p.get('disabled') or not ({p['from_map'],p['to_map']} & reviewed):continue
        a,b=graph.component(p['from_map'],p['cell']),graph.component(p['to_map'],p['target'])
        if a in graph.forward and b not in graph.backward:
            p.update(disabled=True,reason='Original arrival component has no restored return path')
    removed=set()
    for ident in sorted(reviewed & set(map(int,metadata))):
        good=[n for n in graph.forward & graph.backward if graph.nodes[n][0]==ident]
        if not good:
            removed.add(ident);continue
        current=graph.component(ident,metadata[str(ident)]['spawn'])
        if current not in good:
            incoming=next(p['target'] for p in portals if not p.get('disabled') and p['to_map']==ident and graph.component(ident,p['target']) in good)
            d=graph.data[ident]
            forbidden=[p['cell'] for p in portals if p['from_map']==ident]+[r['cell'] for r in residents if r['map_id']==ident]
            spawn=safe_spawn(d,incoming,forbidden,flood(d,incoming))
            metadata[str(ident)]['spawn']=spawn
            reach=flood(d,spawn);coverage={}
            for p in portals:
                if p['from_map']==ident:
                    count=coverage.setdefault(str(p['to_map']),dict(reachable=0,unreachable=0))
                    count['reachable' if reach[p['cell'][1]*d['width']+p['cell'][0]] else 'unreachable']+=1
            reports[str(ident)].update(reachable_cells=sum(reach),exit_coverage=coverage)
    for ident in removed:
        (Path(root)/metadata[str(ident)]['path']).unlink(missing_ok=True)
        metadata.pop(str(ident));reports.pop(str(ident))
    return removed
