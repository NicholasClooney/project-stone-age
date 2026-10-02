"""Strict original handler subsets for explicitly declared quest instances."""
import re


def keyword_warp(source, script, events):
    fields = {}
    for line in source.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, separator, value = line.partition(':')
        if not separator or key in fields:
            raise ValueError('Unsupported keyword source line')
        fields[key] = value
    if set(fields) == {'WARP','FREE','MONEY','FreeMsg','PayMsg','PartyMsg','MoneyMsg'}:
        level_gate = fields['FREE'] == 'LV>49' and re.fullmatch(r'\d+,\d+,\d+', fields['WARP'])
        dragon_gate = fields['FREE'] == 'ITEM=2457&ITEM=2458&ITEM=2459' and fields['WARP'] == '20807,13,35'
        if not (level_gate or dragon_gate) or fields['MONEY'] != '-1':
            raise ValueError('Unreviewed free WarpMan gate')
        return fields['PayMsg'].replace('\\n','\n'), [dict(
            event=-1,type='FREEWARP',condition=fields['FREE'],
            texts={'AcceptMsg':fields['FreeMsg'].replace('\\n','\n')},
            actions={'Warp':fields['WARP']},enabled=True,events=events,source=script,
            source_fields=fields,
            source_rule=('gmsv/npc/npc_eventaction.c:1243-1280,1423-1424,1524-1538; original three-jewel bag check without consumption' if dragon_gate else 'gmsv/npc/npc_warpman.c:228-231,254-268,300-309,393-400,560-566; original free level gate'))]
    if set(fields) == {'WARP','FREE','MONEY','FreeMsg','PayMsg','MoneyMsg','DelItem'}:
        if fields['FREE'] != 'ITEM=2527' or fields['MONEY'] != '-1' or fields['DelItem'] != '2527*1' or fields['WARP'] != '31806,34,6':
            raise ValueError('Unreviewed ticket WarpMan gate')
        return fields['PayMsg'].replace('\\n','\n'), [dict(
            event=-1,type='FREEWARP',condition=fields['FREE'],
            texts={'AcceptMsg':fields['FreeMsg'].replace('\\n','\n')},
            actions={'Warp':fields['WARP'],'DelItem':fields['DelItem']},enabled=True,events=events,source=script,
            source_fields=fields, item_deletion_scope='bag',
            source_rule='gmsv/npc/npc_eventaction.c:856-906,1524-1538; npc_warpman.c:228-231,300-309,393-400')]
    # Do not turn unrelated WarpMan fields/actions into an unconditional door.
    if set(fields) != {'WARP', 'FREE', 'warp_msg', 'nomal_msg'}:
        raise ValueError('Unreviewed keyword WarpMan fields')
    if fields['FREE'] != 'LV>0' or not fields['warp_msg'] or not re.fullmatch(r'\d+,\d+,\d+', fields['WARP']):
        raise ValueError('Unreviewed keyword WarpMan condition or destination')
    return fields['nomal_msg'].replace('\\n', '\n'), [dict(
        event=-1, type='KEYWORD', condition=fields['FREE'],
        texts={'AcceptMsg':fields['nomal_msg'].replace('\\n', '\n')},
        actions={'Warp':fields['WARP']}, keyword=fields['warp_msg'],
        enabled=True, events=events, source=script,
        source_fields=fields,
        source_rule='gmsv/npc/npc_warpman.c:798-844; exact strcmp then FREE and Warp')]


def npc_enemy(source, script, events):
    fields = {}
    for line in source.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, separator, value = line.partition(':')
        if not separator or key in fields:
            raise ValueError('Unsupported NPCEnemy source line')
        fields[key] = value
    allowed = {'entype','dieact','enemyno','startmsg','end msg','deniedmsg',
               'warpfl','warpx','warpy','item','steal','time'} | {f'askbattlemsg{i}' for i in range(1,7)}
    if script in ('400/sb_muge1.arg','400/sb_muge2.arg') and fields.get('start msg') == '':
        allowed.add('start msg')  # Original unused empty spelling, not a new message action.
    if set(fields) - allowed or fields.get('entype') != '2' or fields.get('dieact') not in ('0','1'):
        raise ValueError('Unreviewed NPCEnemy behavior')
    raw = fields.get('enemyno', '')
    if not re.fullmatch(r'\d+(?:,\d+){0,9}',raw):
        raise ValueError('Invalid fixed enemy list')
    enemies = list(map(int,raw.split(',')))
    if any(i <= 0 for i in enemies) or not fields.get('askbattlemsg1'):
        raise ValueError('Missing fixed guard enemies or confirmation')
    dieact=int(fields['dieact'])
    guard={'enemy_ids':enemies,'dieact':dieact}
    actions={'Battle':raw}
    if dieact == 1:
        if any(key in fields for key in ('item','steal','time')):
            raise ValueError('Unreviewed victory Warp item behavior')
        destination = [fields.get(key,'') for key in ['warpfl','warpx','warpy']]
        if any(not re.fullmatch(r'\d+',value) for value in destination):
            raise ValueError('Invalid guard victory destination')
        actions['Warp']=','.join(destination)
    else:
        if fields.get('time') != '300' or fields.get('steal','0') not in ('0','1') or not re.fullmatch(r'\d+(?:,\d+)*',fields.get('item','')):
            raise ValueError('Unreviewed personal guard cooldown or item rule')
        if any(key in fields for key in ('warpfl','warpx','warpy')):
            raise ValueError('Mixed guard death behavior')
        guard.update(required_items=list(map(int,fields['item'].split(','))),steal=int(fields.get('steal','0')),cooldown=300)
        # Missing steal does not consume items; explicit steal:0 is deferred.
        if fields.get('steal') == '0':raise ValueError('Entry item theft is not yet supported')
    texts={f'AcceptMsg{i}':fields[f'askbattlemsg{i}'].replace('\\n','\n')
           for i in range(1,7) if f'askbattlemsg{i}' in fields}
    return '', [dict(event=-1,type='BATTLE',condition='LV>0',texts=texts,
        actions=actions,enabled=True,events=events,
        source=script,source_fields=fields,
        guard=guard,
        source_rule='gmsv/npc/npc_npcenemy.c:83-109,354-397,453-486; existing battle AI only')]


def fixed_enemy_audit(reference, texts, enemy_ids, review=None):
    """Retain source tactics and all seven skill slots, without enabling them."""
    import csv
    import hashlib
    from pathlib import Path
    enemy_path='gmsv/data/enemy.txt';base_path='gmsv/data/enemybase.txt'
    skill_path='gmsv/data/petskill.txt'
    # Enemy/base tables must already be explicitly SHA-pinned by the manifest.
    if enemy_path not in texts or base_path not in texts:
        raise ValueError('Fixed battle requires pinned enemy and base sources')
    enemies={int(r[3]):(line,r) for line,r in enumerate(csv.reader(texts[enemy_path].splitlines()),1) if len(r)>14 and r[3].isdigit()}
    bases={int(r[6]):(line,r) for line,r in enumerate(csv.reader(texts[base_path].splitlines()),1) if len(r)>38 and r[6].isdigit()}
    skill_raw=(Path(reference)/skill_path).read_bytes()
    skills={}
    for line,row in enumerate(csv.reader(skill_raw.decode('gb18030').splitlines()),1):
        if len(row)>6 and row[6].isdigit():skills[int(row[6])]=(line,row)
    result={'enemies':{},'bases':{},'runtime':'existing-ai-only',
            'skills_source_sha256':hashlib.sha256(skill_raw).hexdigest()}
    if review:result['review_document']=review
    for ident in enemy_ids:
        if ident not in enemies:raise ValueError('Missing fixed enemy source')
        line,row=enemies[ident];base=int(row[4])
        if base not in bases:raise ValueError('Missing fixed enemy base source')
        result['enemies'][str(ident)]={'source':enemy_path,'source_line':line,
            'raw_columns':row,'tactics':row[1],'template_id':base}
        line,raw=bases[base];slots=[]
        for slot,value in enumerate(raw[25:32]):
            ident_skill=int(value) if value else 0
            entry={'slot':slot,'id':ident_skill,'raw':value,'original_skill_runtime_restored':False}
            if ident_skill in skills:
                source_line,definition=skills[ident_skill]
                entry.update(source=skill_path,source_line=source_line,raw_columns=definition,name=definition[0],function=definition[2],argument=definition[3])
            slots.append(entry)
        result['bases'][str(base)]={'source':base_path,'source_line':line,'raw_columns':raw,'skills':slots}
    return result
