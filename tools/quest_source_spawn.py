"""The single reviewed Katan area birth; not a general NPC generator."""
import hashlib
from pathlib import Path
from import_world import read_map


def source_area(reference, spec, texts, script, create, fields, review):
    if (script != 'seimu/event/event02_1' or create != 'gmsv/data/npc/seimu/event/event02_n.create'
            or review.get('spawn_policy') != {'mode':'source-area'}
            or fields.get('borncorner') != '230,180,525,200' or fields.get('floorid') != '100'
            or fields.get('time') != '0' or fields.get('createnum') != '1'
            or fields.get('ignoreinvincible') != '1'):
        raise ValueError('Unreviewed source area NPC birth')
    template='gmsv/data/npc/jaruga/event/event.template'
    import re
    matches=[]
    for block in re.findall(r'\{([^}]+)\}',texts.get(template,'')):
        data=dict(line.strip().split('=',1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
        if data.get('templatename')=='changeevent':matches.append(data)
    if len(matches)!=1 or any(matches[0].get(k)!=v for k,v in {'functionset':'ExChangeMan','makeatnobody':'1','makeatnosee':'1'}.items()) or matches[0].get('fly','0')!='0':
        raise ValueError('Missing pinned source area template')
    required=['gmsv/npc/npcgen.c','gmsv/npc/npccreate.c','gmsv/npc/npctemplate.c','gmsv/map/map_deal.c','gmsv/map/readmap.c','gmsv/setup.cf','gmsv/data/map/mapset.txt']
    if any(p not in texts for p in required):raise ValueError('Missing source area collision/generator evidence')
    if not re.search(r'^maptilefile=data/map/mapset.txt\s*$',texts['gmsv/setup.cf'],re.M):raise ValueError('Unreviewed map tile table')
    source=spec.get('world',{}).get('map_sources',{}).get('100',{})
    if source.get('path')!='gmsv/data/map/sainasu/sainasu':raise ValueError('Missing source area map')
    path=Path(reference)/source['path']
    if hashlib.sha256(path.read_bytes()).hexdigest()!=source.get('sha256'):raise ValueError('Changed source area map')
    mid,_,width,height,tiles,objects,_=read_map(path)
    if mid!=100 or width<=525 or height<=200:raise ValueError('Source area map bounds')
    walk={}
    for line in texts['gmsv/data/map/mapset.txt'].splitlines():
        columns=line.split()
        if columns and columns[0].isdigit() and len(columns)>3:walk[int(columns[0])]=int(columns[3])
    mask=[]
    for y in range(180,201):
        for x in range(230,526):
            obj=walk.get(objects[y*width+x],0);tile=walk.get(tiles[y*width+x],0)
            mask.append('1' if obj==2 or (obj==1 and tile==1) else '0')
    if '1' not in mask:raise ValueError('Source area has no valid birth point')
    return dict(rect=[230,180,525,200],walkable=''.join(mask),attempt_seconds=1,
                source_map=source,source_template=template,
                source_rule='npcgen.c:25,54-142,344-375; npccreate.c:535-554; map_deal.c:24-57',
                policy='Original server-wide birth; project per-character server memory, reset on restart')
