"""Explicit region reviews and original scenery doors; no invented links."""
import json
import re
from pathlib import Path


def load_reviews():
    return {p.stem: json.loads(p.read_text()) for p in sorted((Path(__file__).parent/'world_regions').glob('*.json'))}


def portal_key(p):
    return p['from_map'], *p['cell'], p['to_map'], *p['target']


def merge_portals(portals):
    result = {}
    for p in portals:
        key = portal_key(p)
        if key not in result:
            result[key] = dict(p)
        elif 'gate_source' in p:
            result[key].update(gate_source=p['gate_source'], convenience=p['convenience'])
    return list(result.values())


def read_reviewed_portals(reference, reviews):
    ids = {i for review in reviews.values() for i in review['maps']}
    scripts = {s for review in reviews.values() for s in review.get('gate_scripts',[])}
    root = Path(reference)/'gmsv/data/npc'
    result = []
    for path in sorted(root.rglob('*.create')):
        text = path.read_text(errors='replace')
        for match in re.finditer(r'\{([^}]+)\}',text):
            fields = {}
            for line in match[1].splitlines():
                line = line.strip()
                if '=' in line and not line.startswith('#'):
                    k,v = line.split('=',1)
                    fields[k] = v
            if 'floorid' not in fields or 'enemy' not in fields:
                continue
            floor = int(fields['floorid'])
            direct = re.fullmatch(r'npcgen_warp\|(\d+)\|(\d+)\|(\d+)',fields['enemy'])
            script = re.search(r'\|file:([^\s]+)',fields['enemy'])
            gate = None
            if direct:
                target = list(map(int,direct.groups()))
            elif script and script[1] in scripts:
                gate = script[1]
                content = (root/gate).read_text(encoding='gb18030')
                warps = {tuple(map(int,m)) for m in re.findall(r'^WARP:(\d+),(\d+),(\d+)',content,re.M)}
                if not warps:
                    values = [re.search(r'^'+k+r':(\d+)\s*$',content,re.M) for k in ('warpfl','warpx','warpy')]
                    if all(values):warps = {tuple(int(v[1]) for v in values)}
                if len(warps)!=1:
                    raise ValueError(f'Reviewed gate has ambiguous/no WARP: {gate}')
                target = list(next(iter(warps)))
            else:
                continue
            if floor not in ids and target[0] not in ids:
                continue
            if 'borncorner' in fields:
                x,y,x2,y2 = map(int,fields['borncorner'].split(','))
            elif gate and 'borncenter' in fields:
                x,y,w,h = map(int,fields['borncenter'].split(','))
                if (w,h)!=(1,1):raise ValueError(f'Reviewed moving gate: {gate}')
                x2,y2 = x,y
            else:
                continue
            for yy in range(y,y2+1):
                for xx in range(x,x2+1):
                    p = dict(from_map=floor,cell=[xx,yy],to_map=target[0],target=target[1:],
                             source=f'npc/{path.relative_to(root)}:{text[:match.start()].count(chr(10))+1}')
                    if gate:p.update(gate_source=gate,convenience='原版需要任务、战斗或NPC检查，这里直接开放')
                    result.append(p)
    path = Path(reference)/'gmsv/data/map/mapwarp.txt'
    for number,line in enumerate(path.read_text(errors='replace').splitlines(),1):
        m = re.fullmatch(r'NONE:NULL:(\d+),(\d+),(\d+):(\d+),(\d+),(\d+):NULL',line.strip())
        if m:
            a,x,y,b,xx,yy = map(int,m.groups())
            if a in ids or b in ids:
                result.append(dict(from_map=a,cell=[x,y],to_map=b,target=[xx,yy],source=f'map/mapwarp.txt:{number}'))
    return merge_portals(result)
