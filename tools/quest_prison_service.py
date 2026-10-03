"""Five source-pinned prison services; no fees or runtime settlement here."""
import copy
import hashlib
import json
from pathlib import Path
REVIEW=json.loads((Path(__file__).resolve().parents[1]/'client/data/quests/prison-identities.json').read_text())

def parse(spec,texts,script,create,ordinal,fields,review):
    expected=next((a for a in REVIEW['actors'] if a['source_script']==script),None)
    if (not expected or spec['id']!='transmigration-final'
            or review!={'kind':'original_prison','events':[48,49,50,51,52]}
            or create!=expected['source_create'] or ordinal!=expected['source_create_index']):
        raise ValueError('Unreviewed prison identity')
    for path,sha in REVIEW['sources'].items():
        if spec['sources'].get(path)!=sha or hashlib.sha256(texts.get(path,'').encode('gb18030')).hexdigest()!=sha:
            raise ValueError('Unreviewed prison source SHA')
    checks={'enemy':'npcgen_warpman|file:'+script,'floorid':str(expected['map_id']),
            'borncorner':','.join(map(str,expected['cell']*2)),'createnum':'1',
            'graphicname':str(expected['graphic']),'dir':str(expected['facing']),'name':expected['name']}
    if any(fields.get(k)!=v for k,v in checks.items()):raise ValueError('Changed prison create')
    source_fields=dict(line.split(':',1) for line in texts['gmsv/data/npc/'+script].splitlines() if ':' in line and not line.lstrip().startswith('#'))
    if source_fields!=expected['source_fields']:raise ValueError('Changed prison source fields')
    return {k:copy.deepcopy(expected[k]) for k in ['kind','handler','service_id','prison','source_fields']}

def is_reviewed_npc(npc,module_id):
    if module_id!='transmigration-final' or 'prison_role' in npc:return False
    return any(all(npc.get(k)==v for k,v in a.items()) for a in REVIEW['actors'])
