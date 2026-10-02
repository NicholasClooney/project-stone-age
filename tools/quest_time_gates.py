"""Only the reviewed dream-cave MapWarpPoint entrance events."""
import copy
import re

DREAM_GATES = {(400,97,119):(41,11,8,'A'),(400,98,119):(41,11,8,'M'),
               (400,97,120):(41,11,8,'M'),(400,96,119):(41,11,8,'M'),
               (400,87,101):(42,11,8,'N')}
SOURCES = ['gmsv/handletime.c','gmsv/include/handletime.h','gmsv/include/version.h',
           'gmsv/map/map_warppoint.c','gmsv/map/readmap.c','gmsv/data/map/mapwarp.txt',
           'gmsv/data/npc/genout/mugendungeon.create','gmsv/data/npc/genout/mugendungeon2.create']


def reviewed_time_gates(spec, texts):
    mode=spec.get('world',{}).get('time_gates')
    if mode is None:return None
    if mode!='dream-cave' or any(p not in texts for p in SOURCES):
        raise ValueError('Unreviewed time-gate activation or missing source evidence')
    result=[]
    for line_no,line in enumerate(texts['gmsv/data/map/mapwarp.txt'].splitlines(),1):
        m=re.fullmatch(r'NONE:([AMN]):(\d+),(\d+),(\d+):(\d+),(\d+),(\d+):NULL',line.strip())
        if not m:continue
        values=tuple(map(int,m.groups()[1:]));key=values[:3]
        if key not in DREAM_GATES:continue
        if (*values[3:],m[1])!=DREAM_GATES[key]:raise ValueError('Changed original dream entrance')
        result.append(dict(from_map=key[0],cell=list(key[1:]),to_map=values[3],target=list(values[4:]),requires_time=m[1],
                           time_source='gmsv/data/map/mapwarp.txt',time_source_line=line_no))
    if len(result)!=5 or {tuple([p['from_map'],*p['cell']]) for p in result}!=set(DREAM_GATES):
        raise ValueError('Missing original dream MapWarpPoint entrances')
    return result


def apply_time_gates(portals,reviews):
    expected={}
    for review in reviews:
        for gate in review.get('time_gates',[]):
            key=(gate['from_map'],*gate['cell'],gate['to_map'],*gate['target'])
            if key in expected and expected[key]!=gate:raise ValueError('Conflicting original time gate')
            expected[key]=gate
    found=set();result=copy.deepcopy(portals)
    for p in result:
        key=(p['from_map'],*p['cell'],p['to_map'],*p['target'])
        if key not in expected:continue
        gate=expected[key]
        if p.get('source_time_suffix')!=gate['requires_time']:raise ValueError('Create differs from active MapWarpPoint time event')
        p.update({k:gate[k] for k in ['requires_time','time_source','time_source_line']});found.add(key)
    if found!=set(expected):raise ValueError('Missing reviewed create time gate')
    return result
