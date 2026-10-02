"""Pinned five-brothers and golden antelope NPCs; no guessed script actions."""
import csv
import hashlib
import json
import re
from pathlib import Path

SPEC = Path(__file__).with_name('brothers_quest_sources.json')
EVENTS = [28, 29, 30, 31, 54]
MAPS = list(range(31701, 31707)) + list(range(31901, 31912)) + [30600]


def extend(reference, result, parse_script):
    spec = json.loads(SPEC.read_text())
    root = Path(reference)
    texts = {}
    for path, digest in spec['sources'].items():
        raw = (root/path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError('Unreviewed brothers source: '+path)
        texts[path] = raw.decode('gb18030')
    prefix = 'gmsv/data/npc/'
    for create in spec['creates']:
        for block in re.findall(r'\{([^}]+)\}', texts[prefix+create]):
            fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
            match = re.search(r'file:([^\s]+)', fields.get('enemy', ''))
            if not match:
                continue
            ident = match[1]
            if ident not in spec['scripts']:
                continue
            source = texts[prefix+ident]
            kind = spec['scripts'][ident]
            events = [28,31] if ('ev28' in ident or '3170' in ident or 'sb_5b' in ident) else [29,30,54]
            default, branches = '', []
            if kind == 'changeevent':
                # Out-of-scope later quests and a malformed legacy branch remain
                # pinned in provenance. Never rewrite the malformed predicate.
                blocks = re.findall(r'EventNo:.*?EventEnd', source, re.S)
                selected = [b for i,b in enumerate(blocks) if i not in spec.get('excluded_branches', {}).get(ident, [])]
                header = source.split('EventNo:',1)[0]
                # The C engine ignores unknown elItem (ev28_23 typo); do not
                # silently turn it into DelItem and change the original branch.
                selected = [re.sub(r'^elItem:.*$', '', b, flags=re.M) for b in selected]
                default, branches = parse_script(header+'\n'+'\n'.join(selected))
                for branch in branches:
                    branch.update(enabled=True, events=events, source=ident)
            elif kind == 'sign':
                default = source.strip().replace('\\n','\n')
                branches = [dict(event=-1,type='MESSAGE',condition='LV>0',texts={'NomalWindowMsg':default},actions={},enabled=True,events=events,source=ident)]
            elif kind == 'warp':
                fields_script = dict(line.split(':',1) for line in source.splitlines() if ':' in line and not line.startswith('#'))
                default = fields_script.get('NomalMsg',fields_script.get('PayMsg','')).replace('\\n','\n')
                actions = {'Warp':fields_script['WARP']}
                if 'DelItem' in fields_script:actions['DelItem']=fields_script['DelItem']
                branches = [dict(event=-1,type='ACCEPT',condition=fields_script['FREE'],texts={'AcceptMsg':fields_script.get('FreeMsg',''),'ThanksMsg':fields_script.get('FreeMsg','')},actions=actions,enabled=True,events=events,source=ident)]
                for branch in branches:branch['texts']={k:v.replace('\\n','\n') for k,v in branch['texts'].items()}
            elif kind == 'battle':
                f = dict(line.split(':',1) for line in source.splitlines() if ':' in line)
                if f['entype']!='2' or f['dieact']!='1':raise ValueError('Unreviewed guard behavior')
                branches = [dict(event=-1,type='BATTLE',condition='LV>0',texts={'AcceptMsg':f['askbattlemsg1']},actions={'Battle':f['enemyno'],'Warp':','.join(f[k] for k in ['warpfl','warpx','warpy'])},enabled=True,events=events,source=ident)]
            else:raise ValueError(kind)
            corner = fields.get('borncorner', fields.get('borncenter')).split(',')
            npc = dict(id=ident,name=fields.get('name') or '看板',map_id=int(fields['floorid']),cell=list(map(int,corner[:2])),graphic=int(fields['graphicname']),facing=int(re.match(r'\d+',fields['dir'])[0]),role='quest',events=events,text=default,branches=branches)
            if kind=='battle':npc['source_spawn_mode']='NPCEnemy borncenter 1x1; original movement not simulated'
            result['npcs'].append(npc)
    ids = [n['id'] for n in result['npcs'] if n['id'] in spec['scripts']]
    if set(ids)!=set(spec['scripts']) or len(ids)!=len(set(ids)):raise ValueError('Missing/duplicate brothers NPC')
    for line,row in enumerate(csv.reader(texts['gmsv/data/itemset.txt'].splitlines()),1):
        if len(row)<26 or row[16] not in map(str,spec['items']):continue
        ident=int(row[16])
        description=row[2]
        if ident in spec['unimplemented_equipment']:
            description+='\n本项目：保留原物品；装备属性与精灵魔法效果尚未实现。'
        if ident in [2547,2532]:description+='\n'+('首次借出的镜子：归还可领取黄金羚羊，请勿丢弃。' if ident==2547 else '补发的镜子：归还只结束任务，不发黄金羚羊。')
        result['items'][str(ident)]=dict(id=ident,name=row[0],description=description,logical_icon=int(row[17]),stackable=False,source='gmsv/data/itemset.txt',source_line=line,raw_columns=row,logout_vanish=row[78]=='1')
    bases={int(r[6]):(i,r) for i,r in enumerate(csv.reader(texts['gmsv/data/enemybase.txt'].splitlines()),1) if len(r)>38 and r[6].isdigit()}
    for line,row in enumerate(csv.reader(texts['gmsv/data/enemy.txt'].splitlines()),1):
        if len(row)<7 or row[3] not in map(str,spec['reward_enemies']):continue
        ident,species,low,high=map(int,row[3:7]);base_line,base=bases[species]
        if low!=1 or high!=1:raise ValueError('Unreviewed reward level')
        result['reward_pets'][str(ident)]=dict(enemy_id=ident,template_id=species,species=f'original_{species}',level=1,name=base[0],initial=int(base[7]),wild_growth=float(base[8]),weights=list(map(int,base[9:13])),modai=int(base[13]),variable_ai=0,elements=list(map(int,base[15:19])),skill_slots=int(base[34]),sprite=int(base[36]),size=int(base[38]),source='gmsv/data/enemy.txt',source_line=line,base_source='gmsv/data/enemybase.txt',base_source_line=base_line)
    rows=[l.split('|') for l in texts['gmsv/data/jobdaily.txt'].splitlines()]
    for event in EVENTS:
        ends=[r for r in rows if len(r)==4 and r[1]==f'ENDEV={event}']
        for end in ends:
            active=next(r for r in rows if r[0]==end[0] and r[1]==f'NOWEV={event}')
            result['jobs'].append(dict(id=int(end[0]),event=event,title=end[2],completed_label=end[3],active_label=active[3]))
    result['provenance']['brothers_sources']=spec['sources']
    return result
