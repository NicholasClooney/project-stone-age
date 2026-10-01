"""Strictly reviewed original Charm service, consumed by the quest importer."""
import hashlib
import json
import re
from pathlib import Path
SPEC = Path(__file__).with_name('original_charm_sources.json')


def catalog(reference):
    spec = json.loads(SPEC.read_text())
    texts = {}
    for path, digest in spec['sources'].items():
        raw = (Path(reference)/path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError(f'Unreviewed Charm source change: {path}')
        texts[path] = raw.decode('gb18030')
    create = texts['gmsv/data/npc/genout/shop_m.create']
    npcs = []
    # Ignore commented-out definitions, then select only this reviewed handler.
    create = '\n'.join(line for line in create.splitlines() if not line.lstrip().startswith('#'))
    for block in re.findall(r'\{([^}]+)\}', create):
        fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line)
        if fields['enemy'] != 'npcgen_charm':
            continue
        floor = int(fields['floorid'])
        x, y, x2, y2 = map(int, fields['borncorner'].split(','))
        if [floor, x, y] not in [[1005,25,15],[2005,19,15]] or (x,y)!=(x2,y2) or fields['createnum']!='1' or fields['graphicname']!='16065' or fields['name']!='美容师':
            raise ValueError('Unreviewed Charm actor')
        npcs.append(dict(id=f'original/charm/{floor}',name=fields['name'],map_id=floor,cell=[x,y],graphic=16065,facing=int(fields['dir']),role='quest',handler='Charm',branches=[],events=[],text='',source='gmsv/data/npc/genout/shop_m.create'))
    if len(npcs)!=2:
        raise ValueError('Missing reviewed Charm actor')
    # Extract the actual original printf strings; no rewritten dialogue.
    code = texts['gmsv/npc/npc_charm.c']
    strings = []
    for match in re.finditer(r'sprintf\(token,((?:\s*"(?:[^"\\]|\\.)*")+)(?:,cost)?\s*\);',code):
        strings.append(''.join(json.loads(token) for token in re.findall(r'"(?:[^"\\]|\\.)*"',match[1])))
    if len(strings)!=9:
        raise ValueError('Unreviewed Charm windows')
    dialogue = dict(start='欢迎光临，今天要做什麽呢？',choices=[dict(id='charm',text='给我魅力'),dict(id='leave',text='什麽也不做')],full=strings[1],confirm=strings[2],poor=strings[3],success=dict(zip(['GIRL','BOY','CHILDBOY','MAN','WOMAN'],strings[4:])))
    # Player creation assigns CHAR_IMAGETYPE from this table, not gender guesses.
    art = texts['gmsv/include/anim_tbl.h']
    numbers = dict((name,int(number)) for name,number in re.findall(r'#define\s+(SPR_\w+)\s+(\d+)',art))
    types = {}
    for sprite, kind in re.findall(r'\{(SPR_\w+),&player,&lvplayer00,CHAR_IMAGETYPE_(\w+)\}',texts['gmsv/char/char_data.c']):
        if sprite in numbers:types[str(numbers[sprite])]=kind
    for npc in npcs:
        npc['dialogue']=dialogue
        npc['image_types']=types
    return npcs, spec['sources']
