"""Import reviewed original quests only; source changes require explicit review.

Generated dialogue and PNGs stay in ignored assets, never in tracked source.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path
from import_legacy import Archive
from import_original_charm import catalog as charm_catalog

SPEC = Path(__file__).with_name('early_quest_sources.json')


def source_text(reference, relative, spec):
    raw = (Path(reference) / relative).read_bytes()
    if hashlib.sha256(raw).hexdigest() != spec['sources'][relative]:
        raise ValueError(f'Unreviewed source change: {relative}')
    # setup.cf has mixed legacy comment encodings; audited keys are ASCII.
    if relative == 'gmsv/setup.cf':return raw.decode('latin1')
    return raw.decode('gb18030')


def valid_stone_cost(value):
    # Audited NPC_EventGetCost subset; never evaluate arbitrary expressions.
    return value in ('LV*20', 'LV*40') or (
        re.fullmatch(r'[0-9]{1,10}', value) is not None and int(value) <= 2147483647)


def parse_script(text, branch_indices=None):
    if branch_indices is not None:
        from quest_import_common import select_branches
        selected, provenance = select_branches(text, branch_indices)
        default, branches = parse_script(selected)
        for branch, origin in zip(branches, provenance):
            branch.update(origin)
        return default, branches
    branches, current, default = [], None, ''
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line == 'EventEnd':
            if current is None:
                raise ValueError('EventEnd without branch')
            required = {'EventNo', 'TYPE', 'EVENT'}
            if not required <= current.keys():
                raise ValueError('Incomplete quest branch')
            if current['TYPE'] not in ('REQUEST', 'ACCEPT', 'MESSAGE', 'CLEAN'):
                raise ValueError('Unsupported branch type')
            for clause in re.split('[,&]', current['EVENT']):
                if not (re.fullmatch(r'(?:ENDEV|NOWEV|ITEM|SP|LV)(?:!=|=|>|<)\d+(?:\*\d+)?', clause) or re.fullmatch(r'PET>\d+-\d+|PET=\d+-\d+(?:\*1)?', clause)):
                    raise ValueError(f'Unsupported predicate: {clause}')
            texts = {k: v.replace('\\n', '\n') for k, v in current.items() if 'Msg' in k}
            actions = {k: v for k, v in current.items() if k not in required and 'Msg' not in k and k not in ('KeyWord','Break')}
            if not actions.keys() <= {'GetItem', 'DelItem', 'GetStone', 'DelStone', 'EndSetFlg', 'CleanFlg', 'DelPet', 'GetPet', 'GetRandItem', 'Charm', 'NpcWarp'}:
                raise ValueError('Unsupported quest action')
            if 'NpcWarp' in actions and not re.fullmatch(r'\d+\.\d+\.\d+(?:,\d+\.\d+\.\d+)*',actions['NpcWarp']):
                raise ValueError('Unsupported NpcWarp destination list')
            if 'DelStone' in actions and not valid_stone_cost(actions['DelStone']):
                raise ValueError('Unsupported DelStone cost expression')
            for key in ('DelPet', 'GetPet', 'GetRandItem'):
                if key not in actions:
                    continue
                pattern = r'PET[>=]\d+-\d+\*1(?:,PET[>=]\d+-\d+\*1)*' if key == 'DelPet' else (r'\d+' if key == 'GetPet' else r'\d+(?:,\d+)+')
                if not re.fullmatch(pattern, actions[key]):
                    raise ValueError(f'Unsupported {key}: {actions[key]}')
            branch = dict(event=int(current['EventNo']), type=current['TYPE'], condition=current['EVENT'], texts=texts, actions=actions)
            if 'KeyWord' in current:
                if current['TYPE'] != 'ACCEPT' or not current['KeyWord'] or len(current['KeyWord']) > 120:
                    raise ValueError('Unsupported changeevent keyword')
                branch['spoken_keyword'] = current['KeyWord']
            if current.get('Break'):
                if not re.fullmatch(r'\d+(?:,\d+)*', current.get('DelItem','')):
                    raise ValueError('Only unquantified source Break deletion is reviewed')
                branch['source_break'] = True
            branches.append(branch)
            current = None
            continue
        if line == 'Break' and current is not None:
            if 'Break' in current:raise ValueError('Duplicate Break marker')
            current['Break'] = True
            continue
        if ':' not in line:
            raise ValueError(f'Unsupported script line: {line}')
        key, value = line.split(':', 1)
        if key == 'EventNo':
            if current is not None:
                raise ValueError('Unterminated quest branch')
            current = {}
        if current is not None:
            if key in current:
                raise ValueError(f'Duplicate field: {key}')
            current[key] = value
        elif key == 'NomalMainMsg':
            default = value.replace('\\n', '\n')
        else:
            raise ValueError(f'Unsupported global field: {key}')
    if current is not None:
        raise ValueError('Unterminated quest branch')
    return default, branches


def catalog(reference, spec=None):
    spec = spec or json.loads(SPEC.read_text())
    texts = {path: source_text(reference, path, spec) for path in spec['sources']}
    npcs = []
    create = '\n'.join(texts[path] for path in spec['creates'])
    for block in re.findall(r'\{([^}]+)\}', create):
        fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
        script = fields['enemy']
        if not script.startswith('changeevent|file:'):
            raise ValueError('Unsupported NPC handler')
        ident = script.split('file:', 1)[1]
        if ident in spec.get('excluded_scripts', []):
            continue
        if ident not in spec['scripts']:
            raise ValueError(f'Unreviewed NPC: {ident}')
        x, y, x2, y2 = map(int, fields['borncorner'].split(','))
        if (x, y) != (x2, y2) or fields['createnum'] != '1':
            raise ValueError('Unsupported moving/multiple NPC')
        default, branches = parse_script(texts['gmsv/data/npc/' + ident])
        events = spec['script_events'][ident]
        for index, branch in enumerate(branches):
            restriction = spec.get('restricted_conditions', {}).get(ident, {}).get(str(index))
            if restriction:
                if restriction not in branch['condition'].split(','):
                    raise ValueError('Restriction must select a reviewed original alternative')
                branch['source_condition'] = branch['condition']
                branch['disabled_conditions'] = [c for c in branch['condition'].split(',') if c != restriction]
                branch['condition'] = restriction
            # Keep unrelated key-repair dialogue as provenance, never activate it.
            item_ids = {int(i) for i in re.findall(r'ITEM(?:!=|=)(\d+)', branch['condition'])}
            for key in ('GetItem', 'DelItem', 'GetRandItem'):
                item_ids.update(int(i.split('*')[0]) for i in branch['actions'].get(key, '').split(',') if i)
            if 'GetPet' in branch['actions'] and int(branch['actions']['GetPet']) not in spec.get('reward_enemies', []):
                raise ValueError('Unreviewed reward enemy')
            branch['enabled'] = item_ids <= set(spec['items'])
            branch['events'] = list(events) if branch['enabled'] else []
        npcs.append(dict(events=events, id=ident, name=fields['name'], map_id=int(fields['floorid']), cell=[x, y], graphic=int(fields['graphicname']), facing=int(fields['dir']), role='quest', text=default, branches=branches))
    if {n['id'] for n in npcs} != set(spec['scripts']):
        raise ValueError('Missing reviewed NPC')
    items = {}
    for source_line, row in enumerate(csv.reader(texts['gmsv/data/itemset.txt'].splitlines()), 1):
        if len(row) < 26 or row[16] not in map(str, spec['items']):
            continue
        if row[24].strip() or row[25].strip():
            raise ValueError('Explicit pile fields require review')
        ident = int(row[16])
        items[str(ident)] = dict(id=ident, name=row[0], description=row[2], logical_icon=int(row[17]), stackable=False, source='gmsv/data/itemset.txt', source_line=source_line, raw_columns=row)
        if ident in spec.get('recovery_items', []):
            if ident != 2401 or row[3] != '体100' or row[10] != 'ITEM_useRecovery' or row[19:22] != ['16', '0', '1']:
                raise ValueError('Unreviewed recovery item')
            if not re.search(r'^#define\s+_MAGIC_REHPAI\b', texts['gmsv/include/version.h'], re.MULTILINE):
                raise ValueError('Recovery rate configuration requires review')
            items[str(ident)]['use'] = dict(kind='hp_recovery', nominal=100, roll_min=90, roll_max=110, consume_at_full=True, zero_hp_target=True, targets=['self', 'carried_pet'], field_supported=True, battle_supported=False, source='gmsv/item/item_event.c', source_lines=[900,905,963,964,1052,1058], battle_source='gmsv/battle/battle_item.c', battle_source_line=224)
    from quest_item_effects import annotate_item
    for item in items.values():annotate_item(item, reference)
    if set(items) != set(map(str, spec['items'])):
        raise ValueError('Missing reviewed item')
    jobs = []
    event_ids = set()
    for npc in npcs:
        for branch in npc['branches']:
            if not branch['enabled']:
                continue
            if branch['event'] >= 0:
                event_ids.add(branch['event'])
            event_ids.update(int(event) for event in re.findall(r'(?:ENDEV|NOWEV)=(\d+)', branch['condition']))
            for key in ('EndSetFlg', 'CleanFlg'):
                event_ids.update(int(event) for event in branch['actions'].get(key, '').split(',') if event)
    journal_rows = [line.split('|') for line in texts['gmsv/data/jobdaily.txt'].splitlines()]
    job_ids = sorted({int(row[0]) for row in journal_rows if len(row) == 4 and re.fullmatch(r'ENDEV=(\d+)', row[1]) and int(row[1].split('=')[1]) in event_ids})
    for ident in job_ids:
        rows = [row for row in journal_rows if row[0] == str(ident)]
        completed = re.fullmatch(r'ENDEV=(\d+)', rows[0][1]) if len(rows) == 2 and len(rows[0]) == 4 else None
        if not completed or len(rows[1]) != 4 or rows[1][1] != 'NOWEV='+completed[1] or rows[0][2] != rows[1][2]:
            raise ValueError('Unsupported journal definition')
        jobs.append(dict(id=ident, event=int(completed[1]), title=rows[0][2], completed_label=rows[0][3], active_label=rows[1][3]))
    reward_pets = {}
    bases = {int(row[6]): (line, row) for line, row in enumerate(csv.reader(texts.get('gmsv/data/enemybase.txt', '').splitlines()), 1) if len(row) > 36 and row[6].isdigit()}
    for line, row in enumerate(csv.reader(texts.get('gmsv/data/enemy.txt', '').splitlines()), 1):
        if len(row) < 7 or not row[3].isdigit() or int(row[3]) not in spec.get('reward_enemies', []):
            continue
        ident, species, low, high = map(int, row[3:7])
        if low != high or low != 1:
            raise ValueError('Unreviewed reward level')
        base_line, base = bases[species]
        reward_pets[str(ident)] = dict(enemy_id=ident, template_id=species, species=f'original_{species}', level=low, name=base[0], initial=int(base[7]), wild_growth=float(base[8]), weights=list(map(int,base[9:13])), modai=int(base[13]), variable_ai=0, elements=list(map(int,base[15:19])), skill_slots=int(base[34]), sprite=int(base[36]), size=int(base[38]), source='gmsv/data/enemy.txt', source_line=line, base_source='gmsv/data/enemybase.txt', base_source_line=base_line)
    if set(reward_pets) != set(map(str, spec.get('reward_enemies', []))):
        raise ValueError('Missing reviewed reward enemy')
    return dict(version=1, items=items, npcs=npcs, jobs=jobs, reward_pets=reward_pets, provenance=dict(reference_revision=spec['reference_revision'], sources=spec['sources'], client='StoneAge 2.5; logical static graphics, no fallback'))


def quest_npc_image_path(ident):
    """Injective UTF-8 hex name, also distinct on case-insensitive Windows."""
    encoded = ident.encode('utf-8').hex()
    if not encoded or len(encoded) > 240:
        raise ValueError('Quest NPC id exceeds portable filename budget')
    return 'quests/npcs/n-' + encoded + '.png'


def write_quest_catalogs(root, result):
    import copy
    root = Path(root)
    result = copy.deepcopy(result)
    # Runtime code reads this sidecar privately. It is intentionally included
    # in the web core pack for the local backend; its URL is not a secret.
    for module_id, private in result.pop('server_catalogs', {}).items():
        if module_id != 'golden-bui':
            raise ValueError('Unreviewed server catalog output')
        private_target = root/'server/golden-bui.json'
        private_target.parent.mkdir(parents=True, exist_ok=True)
        private_target.write_text(json.dumps(private, ensure_ascii=False, indent=2)+'\n')
    target = root/'quests/catalog.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')


def prepare_npc_art(archive,npcs):
    from import_battle import animations
    art_npcs = npcs.copy()
    for npc in npcs:
        if npc.get('handler') == 'TimeMan':
            for mode in ['main','changed']:
                visual=npc['time_visuals'][mode]
                visual.update(id=npc['id']+':time-'+mode,facing=npc['facing'])
                art_npcs.append(visual)
    for npc in art_npcs:
        if npc['graphic'] in archive.map_ids:
            npc['bitmap_id'] = archive.map_ids[npc['graphic']]
        else:
            frame = animations(archive, npc['graphic'])[f"0_{npc['facing']}"]['frames'][0]
            npc['bitmap_id'] = frame['image']
            npc['source_pose'] = dict(action=0, direction=npc['facing'], frame=0)
    return art_npcs


def write_npc_art(archive,art_npcs,root):
    for npc in art_npcs:
        bitmap = npc['bitmap_id']
        entry = archive.entries[bitmap]
        npc.update(path=quest_npc_image_path(npc['id']), offset=[entry['x'], entry['y']], bitmap_id=bitmap)
        target = root/npc['path']; target.parent.mkdir(parents=True, exist_ok=True)
        archive.image(bitmap).save(target)


def run(source, reference, output):
    spec = json.loads(SPEC.read_text())
    result = catalog(reference, spec)
    from import_brothers_quests import extend
    result = extend(reference, result, parse_script)
    from quest_import_common import extend_registered_modules
    result = extend_registered_modules(reference, result)
    result["service_npcs"], result["provenance"]["charm_sources"] = charm_catalog(reference)
    for relative, expected in spec['client_sources'].items():
        if hashlib.sha256((Path(source)/relative).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Unreviewed client source change: {relative}')
    archive = Archive(source)
    result["provenance"]["client_sources"] = {
        "data/adrn_15.bin": hashlib.sha256((Path(source)/"data/adrn_15.bin").read_bytes()).hexdigest()}
    root = Path(output)
    # Validate all graphics before writing any catalog or art.
    art_npcs=prepare_npc_art(archive,result['npcs']+result['service_npcs'])
    graphics = [i['logical_icon'] for i in result['items'].values()]
    if any(g not in archive.map_ids for g in graphics):
        raise ValueError('Reviewed static graphics missing from 2.5 client')
    write_npc_art(archive,art_npcs,root)
    for item in result['items'].values():
        bitmap = archive.map_ids[item['logical_icon']]
        item.update(bitmap_id=bitmap, icon_path=f"quests/items/{item['id']}.png")
        target = root/item['icon_path']; target.parent.mkdir(parents=True, exist_ok=True)
        archive.image(bitmap).save(target)
    write_quest_catalogs(root, result)
    print(f"Imported {len(result['npcs'])} reviewed quest NPCs and {len(result['items'])} items")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--reference', default='references/chenmingbiao-stone-age')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.reference, args.output)
