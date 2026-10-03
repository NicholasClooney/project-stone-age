"""Evidence validation for stage-one resources; never enables quest branches."""
import hashlib
import re
import struct
from pathlib import Path


def validate(reference, spec, texts):
    seen=set()
    for record in spec['reviewed_bindings']:
        create=record['create'];script=record['script']
        if create not in texts or 'gmsv/data/npc/'+script not in texts:
            raise ValueError('Unpinned transmigration binding')
        blocks=list(re.finditer(r'\{([^}]+)\}',texts[create]))
        index=record['source_create_index']
        if type(index) is not int or not 0<=index<len(blocks):raise ValueError('Missing original create block')
        match=blocks[index]
        fields=dict(line.strip().split('=',1) for line in match[1].splitlines()
                    if '=' in line and not line.lstrip().startswith('#'))
        cell=list(map(int,fields.get('borncorner',fields.get('borncenter','')).split(',')))[:2]
        if (fields.get('enemy')!=record['handler']+'|file:'+script
                or int(fields['floorid'])!=record['map_id'] or cell!=record['cell']
                or record['source_line']!=texts[create][:match.start()].count('\n')+1):
            raise ValueError('Transmigration binding differs from actual create')
        identity=(create,index)
        if identity in seen:raise ValueError('Duplicate reviewed create block')
        seen.add(identity)
    for ident,record in spec['staged_world']['map_sources'].items():
        raw=(Path(reference)/record['path']).read_bytes()
        if (raw[:6]!=b'LS2MAP' or struct.unpack_from('>H',raw,6)[0]!=int(ident)
                or hashlib.sha256(raw).hexdigest()!=record['sha256']):
            raise ValueError('Transmigration map identity or SHA changed')


def portals(reference, reviews):
    """Pinned ordinary doors only. Scripted gates remain NPC transactions."""
    result=[]
    for review in reviews:
        maps={int(i) for i in review.get('map_sources',{})}
        for path, expected in review.get('portal_sources',{}).items():
            raw=(Path(reference)/path).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('Staged portal source changed')
            text=raw.decode('gb18030')
            if path.endswith('.create'):
                for match in re.finditer(r'\{([^}]+)\}',text):
                    fields=dict(line.strip().split('=',1) for line in match[1].splitlines()
                                if '=' in line and not line.lstrip().startswith('#'))
                    target=re.fullmatch(r'npcgen_warp\|(\d+)\|(\d+)\|(\d+)',fields.get('enemy',''))
                    if not target:continue
                    floor=int(fields['floorid']);dest,x,y=map(int,target.groups())
                    if floor not in maps and dest not in maps:continue
                    x1,y1,x2,y2=map(int,fields['borncorner'].split(','))
                    for cy in range(y1,y2+1):
                        for cx in range(x1,x2+1):
                            result.append(dict(from_map=floor,cell=[cx,cy],to_map=dest,target=[x,y],source=path+':'+str(text[:match.start()].count('\n')+1)))
            elif path=='gmsv/data/map/mapwarp.txt':
                for line,raw_line in enumerate(text.splitlines(),1):
                    match=re.fullmatch(r'NONE:NULL:(\d+),(\d+),(\d+):(\d+),(\d+),(\d+):NULL',raw_line.strip())
                    if not match:continue
                    floor,x,y,dest,tx,ty=map(int,match.groups())
                    if floor in maps or dest in maps:result.append(dict(from_map=floor,cell=[x,y],to_map=dest,target=[tx,ty],source=path+':'+str(line)))
            else:raise ValueError('Unreviewed portal source format')
    return result
