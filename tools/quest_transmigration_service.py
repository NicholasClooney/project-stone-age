"""Only the reviewed original king service; no settlement or pet rebirth."""
import hashlib
import re

SCRIPT = '777/ten.arg'
CREATE = 'gmsv/data/npc/giiru/event/sikkoku/sikkoku.create'
TEMPLATE = 'gmsv/data/npc/777/allnpc.template'
IDENT = SCRIPT+'@32021:31:28'
EVENTS = [48,49,50,51,52]
RULES = 'original-1to5-anson20-v1'
SOURCES = {
    CREATE: 'db20a0b44bebd3d6dedb1d67dec42a9dd78bd82b82ebc8107789db199a08ed13',
    'gmsv/data/npc/'+SCRIPT: '5d09f42c64a61c3220a01a5a0e82340672fb67ead03b818c4f6457421832c852',
    TEMPLATE: 'ac9a26db80ed4e66abe2d61c4e7979034dcf23e509f287899112b4e9c878764f',
}
ROUND_KEYS = {'startmsg','mainmsg','yesmsg1','yesmsg2','nomsg','nonemsg'}
VILLAGES = {
    'samugiru': (1,[1377,1380,1379,1378,1381],[1006,15,22],4,3),
    'marinasu': (2,[1380,1379,1378,1377,1381],[2006,20,16],6,2),
    'jaja': (4,[1379,1378,1377,1380,1381],[3006,21,16],4,3),
    'karutarna': (8,[1378,1377,1380,1379,1381],[4006,14,20],6,2),
}

def parse(spec, texts, script, create, ordinal, fields, review):
    if (spec['id']!='transmigration-final' or script!=SCRIPT or create!=CREATE
            or ordinal!=5 or review!={'kind':'original_transmigration','events':EVENTS}):
        raise ValueError('Unreviewed transmigration service identity')
    for path, digest in SOURCES.items():
        if (spec['sources'].get(path)!=digest
                or hashlib.sha256(texts.get(path,'').encode('gb18030')).hexdigest()!=digest):
            raise ValueError('Unreviewed transmigration service source: '+path)
    expected = {'floorid':'32021','borncorner':'31,28,31,28','createnum':'1',
                'graphicname':'100444','dir':'4','enemy':'npc_transmigration|file:'+SCRIPT,'name':'精灵王'}
    if any(fields.get(k)!=v for k,v in expected.items()):
        raise ValueError('Changed original king create')
    templates = [dict(line.strip().split('=',1) for line in block.splitlines()
                     if '=' in line and not line.lstrip().startswith('#'))
                 for block in re.findall(r'\{([^}]+)\}', texts[TEMPLATE])]
    matches = [t for t in templates if t.get('templatename')=='npc_transmigration']
    if len(matches)!=1 or matches[0].get('functionset')!='transmigration':
        raise ValueError('Changed original king template')
    header, rounds = {}, {}
    section = 'header'
    for line in texts['gmsv/data/npc/'+SCRIPT].splitlines():
        if not line.strip() or line.lstrip().startswith('#'):continue
        key, sep, value = line.partition(':')
        if not sep:raise ValueError('Invalid king source field')
        if key=='PETTRANS':section='pet';continue
        if key=='TENSEI':
            count=int(value)
            if count in rounds:raise ValueError('Duplicate king round')
            rounds[count]={};section=count;continue
        target=header if section=='header' else rounds[section] if isinstance(section,int) else None
        if target is None:continue  # Pinned PETTRANS provenance; never executable.
        if key in target:raise ValueError('Duplicate king text')
        target[key]=value
    if set(header)!=set(VILLAGES)|{'maxmsg'} or set(rounds)!=set(range(1,7)):
        raise ValueError('Changed original king sections')
    result={'schema':1,'rules':RULES,'rounds':[],'villages':[],
            'maxmsg':header['maxmsg'].replace('\\n','\n')}
    for count in range(1,6):
        if set(rounds[count])!=ROUND_KEYS:raise ValueError('Changed king round texts')
        result['rounds'].append({'count':count,'texts':{k:v.replace('\\n','\n') for k,v in rounds[count].items()}})
    for key,(bit,presents,location,item,pet) in VILLAGES.items():
        value=f'Item={item},Pet={pet},Present='+'.'.join(map(str,presents))+',Warp='+'.'.join(map(str,location))
        if header[key]!=value:raise ValueError('Changed king village reward')
        result['villages'].append(dict(key=key,savepoint_bit=bit,presents=presents.copy(),
            location=dict(map_id=location[0],x=location[1],y=location[2]),source_item=item,source_pet=pet))
    return dict(kind='original_transmigration',handler='Transmigration',service_id=SCRIPT,transmigration=result)

def is_reviewed_npc(npc,module_id):
    return (module_id=='transmigration-final' and npc.get('kind')=='original_transmigration'
            and npc.get('handler')=='Transmigration' and npc.get('service_id')==SCRIPT
            and npc.get('id')==IDENT and npc.get('source_script')==SCRIPT
            and npc.get('source_create')==CREATE and npc.get('source_create_index')==5
            and npc.get('map_id')==32021 and npc.get('cell')==[31,28]
            and npc.get('graphic')==100444 and npc.get('facing')==4 and npc.get('name')=='精灵王'
            and npc.get('branches')==[] and npc.get('events')==EVENTS
            and npc.get('transmigration',{}).get('rules')==RULES)
