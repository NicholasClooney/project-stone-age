"""Source-locked quest 44 sidecar. Never registers or activates itself."""
import csv
import hashlib
import json
import re
from pathlib import Path

SPEC = Path(__file__).with_name('golden_bui_quest_sources.json')
PREFIX = 'gmsv/data/npc/'
ROUTE_MAPS = [*range(800,812), *range(820,830), 831, *range(840,852), 2020, 4020]


def source_texts(reference, spec):
    texts = {}
    for path, digest in spec['sources'].items():
        raw = (Path(reference)/path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError('Unreviewed golden Bui source: '+path)
        if '/map/' not in path:
            texts[path] = raw.decode('gb18030', errors='replace')
    return texts


def bindings(text, source):
    for index, match in enumerate(re.finditer(r'\{([^}]+)\}', text)):
        fields = dict(line.strip().split('=',1) for line in match[1].splitlines()
                      if '=' in line and not line.lstrip().startswith('#'))
        corners = list(map(int, fields.get('borncorner','0,0,0,0').split(',')))
        if corners[:2] != corners[2:] or fields.get('createnum') != '1':
            continue
        fields.update(source_create=source, source_create_index=index,
                      source_line=text[:match.start()].count('\n')+1,
                      map_id=int(fields['floorid']), cell=corners[:2])
        yield fields


def fields_of(text):
    return dict(line.split(':',1) for line in text.splitlines()
                if ':' in line and not line.startswith('#'))


def thresholds(raw, value_type=str):
    parts = raw.split(',')
    if len(parts)%2:
        raise ValueError('Incomplete quiz threshold')
    return [dict(min_correct=int(parts[i]), value=value_type(parts[i+1]))
            for i in range(0,len(parts),2)]


def questions(text):
    result = []
    for line, row in enumerate(csv.reader(text.splitlines()),1):
        if not row or row[0].startswith('#') or not row[0].strip():
            continue
        # NPC_readQuiz ignores rows without all nine comma fields.
        if len(row)<9:
            continue
        no, kind, level, answer_type, answer = map(int,row[:5])
        if answer_type not in (1,2,4) or not 1<=answer<=3:
            raise ValueError('Unsupported original question: '+str(no))
        result.append(dict(id=no, type=kind, level_mask=level, answer_type=answer_type,
                           answer=answer-1, text=row[5], options=row[6:9], source_line=line))
    return result


def eligible(question, config):
    return ((config['type_mask'] & (1 << (question['type']-1))) != 0
            and config['level_mask'] & question['level_mask'] == question['level_mask']
            and config['answer_mask'] & question['answer_type'] == question['answer_type'])


def build_sidecar(reference, spec=None):
    spec = json.loads(SPEC.read_text()) if spec is None else spec
    texts = source_texts(reference,spec)
    question_rows = questions(texts['gmsv/data/question.txt'])
    npcs, services, seen = [], {}, set()
    for create in spec['sidecar_creates']:
        for f in bindings(texts[create],create):
            match = re.fullmatch(r'npcgen_(quiz|janken|warpman)\|file:(\S+)',f['enemy'])
            if not match or match[2] not in spec['sidecar_scripts']:
                continue
            kind, script = match.groups()
            if spec['sidecar_scripts'][script] != kind:
                raise ValueError('Mismatched reviewed handler')
            config = fields_of(texts[PREFIX+script])
            rule = dict(kind=kind, original_fields=config)
            if kind != 'warpman':
                entry = config['EntryItem'].split('*')
                rule.update(entry_item=int(entry[0]), entry_count=int(entry[1]))
            if kind == 'quiz':
                rule.update(type_mask=int(config['Type']), level_mask=int(config['Level']),
                            answer_mask=int(config['Answer']), count=int(config['Quiznum']),
                            borders=thresholds(config['Border']),
                            warps=thresholds(config['Warp'],lambda s:list(map(int,s.split('.')))),
                            rewards=thresholds(config['GetItem'],int) if 'GetItem' in config else [])
                rule['questions']=[q for q in question_rows if eligible(q,rule)]
                if len(rule['questions'])<rule['count']:
                    raise ValueError('Insufficient original question pool')
            elif kind == 'janken':
                rule.update(win_warp=list(map(int,config['WinWarp'].split(','))),
                            lose_warp=list(map(int,config['LoseWarp'].split(','))))
            else:
                rule.update(warp=list(map(int,config['WARP'].split(','))),condition=config['FREE'],
                            del_items=config.get('DelItem',''))
            ident=f'{script}@{f["map_id"]}:{f["cell"][0]}:{f["cell"][1]}'
            npcs.append(dict(id=ident, source_script=script, source_create=create,
                             source_create_index=f['source_create_index'], source_line=f['source_line'],
                             map_id=f['map_id'],cell=f['cell'],name=f['name'],
                             graphic=int(f['graphicname']),facing=int(f['dir']),
                             role='quest',events=[44],kind='golden_bui_'+('gate' if kind=='warpman' else kind),
                             text='',branches=[],service_id=script))
            services[script]=rule
            seen.add(script)
    if seen != set(spec['sidecar_scripts']):
        raise ValueError('Missing reviewed quiz/janken binding')
    portals, conflicts = [], []
    by_cell = {}
    create='gmsv/data/npc/genout/quiz.create'
    for f in bindings(texts[create],create):
        match=re.fullmatch(r'npcgen_warp\|(\d+)\|(\d+)\|(\d+)',f['enemy'])
        if not match: continue
        target=list(map(int,match.groups()))
        if f['map_id'] not in ROUTE_MAPS+[2000,4000] or target[0] not in ROUTE_MAPS+[2000,4000]:continue
        portal=dict(from_map=f['map_id'],cell=f['cell'],to_map=target[0],target=target[1:],
                    source=f'quiz.create:{f["source_line"]}',source_create_index=f['source_create_index'])
        key=(f['map_id'],*f['cell'])
        if key in by_cell:
            conflicts.append(dict(selected=by_cell[key],ignored=portal,rule='original-first-created'))
        else:
            by_cell[key]=portal;portals.append(portal)
    import import_encounters as encounters
    catalog=encounters.build(Path(reference)/'gmsv/data')
    drops=[]
    for enemy_id in range(1287,1305):
        enemy=catalog['enemies'][str(enemy_id)]
        group_id=708+(enemy_id-1287)//6
        for slot in enemy['drops']:
            drops.append(dict(enemy_id=enemy_id,item_id=slot['item_id'],source='gmsv/data/enemy.txt',
                              source_line=enemy['source_line'],probability=slot['probability'],
                              group_ids=[group_id],audit='Original random dojo disciple; existing AI, tactics retained in audit.'))
    choices=[dict(from_map=p['from_map'],cell=p['cell'],to_map=p['to_map'],to_cell=p['target'],
                  source='gmsv/data/npc/genout/quiz.create',source_line=int(p['source'].split(':')[1]),
                  reason='original-first-created: npccreate append; npcgen ascending; MAP tail; EVENT first match')
             for p in portals]
    return dict(version=1,module_id='golden-bui',npcs=npcs,services=services,
                items={},reward_pets={},jobs=[],drops=drops,
                world=dict(map_sources=spec['map_sources'],restored_scripts=list(spec['sidecar_scripts']),portal_choices=choices),
                portal_conflicts=conflicts,
                provenance=dict(reference_revision=spec['reference_revision'],sources=spec['sources']))


def build(reference):
    from quest_import_common import load_quest_module
    sidecar=build_sidecar(reference)
    spec=json.loads(SPEC.read_text())
    static_sources=set(spec['creates']) | {PREFIX+s for s in spec['scripts']} | {
        'gmsv/data/'+name for name in ('itemset.txt','jobdaily.txt','enemy.txt','enemybase.txt')}
    static_spec=dict(spec,sources={p:h for p,h in spec['sources'].items() if p in static_sources})
    result=load_quest_module(reference,static_spec)
    result['npcs'].extend(sidecar.pop('npcs'))
    result['provenance']['golden_bui_sources']=sidecar['provenance']['sources']
    for key in ('services','world','drops','portal_conflicts'):
        result[key]=sidecar[key]
    return result


if __name__ == '__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference',type=Path,default=Path('references/chenmingbiao-stone-age'))
    parser.add_argument('--output',type=Path)
    args=parser.parse_args();data=build(args.reference)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    else:print(f'{len(data["npcs"])} reviewed challenges, {len(data["portals"])} portals')
