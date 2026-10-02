"""Shared, fail-closed import of explicitly registered original quest modules.

Only raw source branches selected by the manifest reach the strict parser.
A script is provenance; an NPC id identifies one actual create instance.
"""
import copy
import json
import re
from pathlib import Path

REGISTRY = Path(__file__).resolve().parents[1] / 'client/data/quest-modules.json'
PREFIX = 'gmsv/data/npc/'


def select_branches(text, indices):
    header, blocks, current, start = [], [], None, 0
    for line_number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('EventNo:'):
            if current is not None:
                raise ValueError('Unterminated quest branch')
            current, start = [line], line_number
        elif stripped == 'EventEnd':
            if current is None:
                raise ValueError('EventEnd without branch')
            current.append(line)
            blocks.append(('\n'.join(current), start))
            current = None
        elif current is not None:
            current.append(line)
        elif not blocks:
            header.append(line)
        elif stripped and not stripped.startswith('#'):
            raise ValueError('Unsupported text outside quest branch')
    if current is not None:
        raise ValueError('Unterminated quest branch')
    if not isinstance(indices, list) or not indices or any(type(i) is not int or i < 0 or i >= len(blocks) for i in indices) or indices != sorted(set(indices)):
        raise ValueError('Branch indices must be nonempty, unique, ordered original indices')
    return '\n'.join(header + [blocks[i][0] for i in indices]), [
        dict(source_branch_index=i, source_line=blocks[i][1]) for i in indices]


def instance_id(script, map_id, cell):
    return f'{script}@{int(map_id)}:{int(cell[0])}:{int(cell[1])}'


def apply_branch_supplements(spec, script, branches):
    """Project-authorized additions retain the exact source actions/texts."""
    for extra in spec.get('supplements', []):
        if extra.get('script') != script:
            continue
        if type(extra.get('branch')) is not int or not extra.get('annotation') or not extra.get('approval'):
            raise ValueError('Missing supplement authorization evidence')
        matches = [b for b in branches if b.get('source_branch_index') == extra.get('branch')]
        if len(matches) != 1:
            raise ValueError('Supplement branch is not selected')
        branch = matches[0]
        if 'project_supplement' in branch:
            raise ValueError('Duplicate branch supplement')
        allowed = {'script', 'branch', 'annotation', 'approval'}
        if 'end_flags_add' in extra:
            allowed.add('end_flags_add')
            if (script != 'sainasu/event/event13_1' or extra['branch'] != 0
                    or extra['end_flags_add'] != [14] or branch['actions'].get('EndSetFlg') != '13'):
                raise ValueError('Unapproved completion flag supplement')
        if 'confirmation_text' in extra:
            allowed.add('confirmation_text')
            if (script != 'sainasu/event/event13_2' or extra['branch'] != 0
                    or branch['type'] != 'CLEAN' or branch['actions'].get('CleanFlg') != '13'
                    or not isinstance(extra['confirmation_text'], str) or not extra['confirmation_text'].strip()):
                raise ValueError('Unapproved CLEAN confirmation supplement')
        if set(extra) - allowed or not ({'end_flags_add', 'confirmation_text'} & set(extra)):
            raise ValueError('Unsupported branch supplement')
        branch['source_actions'] = copy.deepcopy(branch['actions'])
        branch['source_texts'] = copy.deepcopy(branch['texts'])
        branch['project_supplement'] = copy.deepcopy(extra)
        if 'end_flags_add' in extra:
            branch['actions']['EndSetFlg'] = '13,14'
        if 'confirmation_text' in extra:
            branch['confirmation_text'] = extra['confirmation_text']


def reviewed_static_drops(spec, texts):
    """Activate only complete, explicitly reviewed drop slots from pinned enemies."""
    import csv
    from import_encounters import drop_slots
    declared = spec.get('drops', [])
    if not isinstance(declared, list):
        raise ValueError('Reviewed drops must be a list')
    if not declared:
        return []
    path = 'gmsv/data/enemy.txt'
    if path not in texts:
        raise ValueError('Reviewed drops require SHA-pinned enemy source')
    enemies = {int(row[3]): (line, row) for line, row in
               enumerate(csv.reader(texts[path].splitlines()), 1)
               if len(row) > 33 and row[3].isdigit()}
    seen = set()
    result = []
    for entry in declared:
        if (not isinstance(entry, dict) or set(entry) - {'source','enemy_id','item_id','probability','audit','source_line'}
                or entry.get('source') != path or not isinstance(entry.get('audit'), str) or not entry['audit'].strip()
                or any(type(entry.get(key)) is not int for key in ('enemy_id','item_id','probability'))
                or entry['enemy_id'] not in enemies or entry['item_id'] not in spec['items']):
            raise ValueError('Invalid static reviewed drop declaration')
        line, row = enemies[entry['enemy_id']]
        identity = (entry['enemy_id'], entry['item_id'], entry['probability'])
        if identity in seen or ('source_line' in entry and entry['source_line'] != line):
            raise ValueError('Duplicate or incorrect reviewed drop source')
        slots = [slot for slot in drop_slots(row)
                 if (slot['item_id'], slot['probability']) == identity[1:]]
        if not slots or not 0 <= entry['probability'] <= 1000:
            raise ValueError('Reviewed drop differs from pinned original slot')
        seen.add(identity)
        result.append(dict(entry, source_line=line, source_slots=slots,
                           source_raw_columns=row))
    # Runtime activation is per enemy. Do not silently enable an undeclared
    # second slot (including a second probability for the same item).
    for enemy_id in {entry['enemy_id'] for entry in declared}:
        expected = {(enemy_id, slot['item_id'], slot['probability'])
                    for slot in drop_slots(enemies[enemy_id][1])}
        if expected != {identity for identity in seen if identity[0] == enemy_id}:
            raise ValueError('All original drop slots of an activated enemy require review')
    return result


def missing_condition_reviews(spec, texts):
    """Explicit source inconsistencies; these ids never become usable items."""
    import csv
    declared=spec.get('missing_condition_items',[])
    if not isinstance(declared,list):raise ValueError('Missing condition item reviews must be a list')
    rows=csv.reader(texts['gmsv/data/itemset.txt'].splitlines())
    defined={int(row[16]) for row in rows if len(row)>16 and row[16].isdigit()}
    result={}
    for entry in declared:
        if (not isinstance(entry,dict) or set(entry)!={'id','script','branch','reason'}
                or type(entry['id']) is not int or entry['id']<=0
                or type(entry['branch']) is not int or entry['branch']<0
                or not isinstance(entry['reason'],str) or not entry['reason'].strip()
                or entry['script'] not in spec['scripts']):
            raise ValueError('Invalid missing condition item source review')
        key=(entry['script'],entry['branch'],entry['id'])
        if key != ('giiru/event/giruev2_1',0,2391):
            raise ValueError('Unapproved missing condition item exception')
        if (entry['id'] in defined or entry['id'] in spec['items'] or key in result
                or str(entry['id']) in spec.get('item_notes',{})):
            raise ValueError('Missing condition item must be absent and condition-only')
        result[key]=copy.deepcopy(entry)
    return result


def load_quest_module(reference, manifest):
    from import_early_quests import catalog, parse_script, source_text
    spec = json.loads(Path(manifest).read_text()) if isinstance(manifest, (str, Path)) else copy.deepcopy(manifest)
    if spec.get('version') != 1 or not re.fullmatch(r'[a-z][a-z0-9-]*', spec.get('id', '')):
        raise ValueError('Invalid quest module identity')
    texts = {path: source_text(reference, path, spec) for path in spec['sources']}
    # Reuse the audited item/reward importers without importing their NPCs.
    base_spec = dict(spec, creates=[], scripts=[], script_events={})
    result = catalog(reference, base_spec)
    result['module_id'] = spec['id']
    result['jobs'] = copy.deepcopy(spec.get('jobs', []))
    drops = reviewed_static_drops(spec, texts)
    if drops:result['drops'] = drops
    missing_reviews=missing_condition_reviews(spec,texts)
    used_missing=set()
    declared = spec['scripts']
    handlers = spec.get('handlers', {})
    if set(declared) & set(handlers):
        raise ValueError('Handler duplicates changeevent declaration')
    if any(review.get('kind') not in ('warpman','npcenemy') for review in handlers.values()):
        raise ValueError('Quest handler not yet supported')
    selected_scripts = {**declared, **handlers}
    if any(extra.get('script') not in declared for extra in spec.get('supplements', [])):
        raise ValueError('Supplement script is not selected')
    seen = set()
    for create in spec['creates']:
        for ordinal, block in enumerate(re.findall(r'\{([^}]+)\}', texts[create])):
            fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
            match = re.fullmatch(r'([^|]+)\|file:(\S+)', fields.get('enemy', ''))
            if not match or match[2] not in selected_scripts:
                continue
            script = match[2]
            review = selected_scripts[script]
            kind = review.get('kind', 'changeevent')
            if kind == 'npcenemy':
                template_bindings = []
                for path, text in texts.items():
                    if not path.endswith('.template'):continue
                    for template_block in re.findall(r'\{([^}]+)\}', text):
                        template = dict(line.strip().split('=',1) for line in template_block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
                        if template.get('templatename') == match[1]:template_bindings.append(template.get('functionset'))
                if template_bindings != ['NPCEnemy']:
                    raise ValueError('Missing or ambiguous pinned NPCEnemy template binding')
            elif match[1] != ('npcgen_warpman' if kind == 'warpman' else 'changeevent'):
                raise ValueError('Reviewed handler differs from actual create binding')
            corners = list(map(int, fields.get('borncorner', fields.get('borncenter','')).split(',')))
            fixed_spawn = len(corners) == 4 and (corners[:2] == corners[2:] if 'borncorner' in fields else kind == 'npcenemy' and corners[2:] == [1,1])
            if not fixed_spawn or fields['createnum'] != '1':
                raise ValueError('Moving/multiple NPC requires a reviewed handler')
            map_id, cell = int(fields['floorid']), corners[:2]
            # Optional instance allowlist uses the same public stable id.
            ident = instance_id(script, map_id, cell)
            if 'instances' in review and ident not in review['instances']:
                continue
            if script in handlers:
                from quest_source_handlers import keyword_warp, npc_enemy, fixed_enemy_audit
                parser = npc_enemy if kind == 'npcenemy' else keyword_warp
                default, branches = parser(texts[PREFIX + script], script, review['events'])
                if kind == 'npcenemy':
                    branches[0]['combat_audit'] = fixed_enemy_audit(reference, texts, branches[0]['guard']['enemy_ids'], spec.get('combat_audit'))
                    guard=branches[0]['guard']
                    if not set(guard.get('required_items', [])) <= set(spec['items']):
                        raise ValueError('Unreviewed NPCEnemy required item')
                    from import_encounters import drop_slots
                    for enemy_id, record in branches[0]['combat_audit']['enemies'].items():
                        for drop in drop_slots(record['raw_columns']):
                            if drop['item_id'] not in spec['items']:
                                raise ValueError('Unreviewed guard reward item')
                            entry=dict(enemy_id=int(enemy_id),item_id=drop['item_id'],probability=drop['probability'],source=record['source'],source_line=record['source_line'],audit='Pinned NPCEnemy original drop; existing AI only')
                            if entry not in result.setdefault('drops',[]):result['drops'].append(entry)

            else:
                default, branches = parse_script(texts[PREFIX + script], review['branches'])
                apply_branch_supplements(spec, script, branches)
            events = review['events']
            if not events or any(type(e) is not int or not 0 < e < 192 for e in events):
                raise ValueError('Invalid module events')
            for branch in branches:
                condition_ids = {int(i) for i in re.findall(r'ITEM(?:!=|=)(\d+)', branch['condition'])}
                for item_id in condition_ids - set(spec['items']):
                    key=(script,branch.get('source_branch_index'),item_id)
                    if key not in missing_reviews:raise ValueError('Unreviewed branch condition item')
                    if branch['condition'] != 'ENDEV=27&ITEM!=2391':raise ValueError('Unapproved missing item condition')
                    review=missing_reviews[key]
                    branch.setdefault('missing_condition_items',[]).append(dict(review,source=PREFIX+script,source_line=branch['source_line']))
                    used_missing.add(key)
                action_ids=set()
                for key in ('GetItem', 'DelItem', 'GetRandItem'):
                    action_ids.update(int(i.split('*')[0]) for i in branch['actions'].get(key, '').split(',') if i)
                if not action_ids <= set(spec['items']):
                    raise ValueError('Unreviewed branch action item')
                if 'GetPet' in branch['actions'] and int(branch['actions']['GetPet']) not in spec.get('reward_enemies', []):
                    raise ValueError('Unreviewed reward enemy')
                branch.update(enabled=True, events=list(events), source=script)
            npc = dict(id=ident, source_script=script, source_create=create, source_create_index=ordinal,
                       events=list(events), name=fields['name'], map_id=map_id, cell=cell,
                       graphic=int(fields['graphicname']), facing=int(fields['dir']), role='quest', text=default, branches=branches)
            if kind == 'npcenemy':
                npc['source_spawn_mode'] = 'NPCEnemy borncenter 1x1; original movement not simulated'
            if ident in seen:
                raise ValueError('Duplicate quest instance: ' + ident)
            seen.add(ident)
            result['npcs'].append(npc)
    if {n['source_script'] for n in result['npcs']} != set(selected_scripts):
        raise ValueError('Missing actual create binding for reviewed script')
    if used_missing != set(missing_reviews):
        raise ValueError('Missing condition item review does not match a selected source branch')
    for script, review in selected_scripts.items():
        if 'instances' in review and set(review['instances']) != {n['id'] for n in result['npcs'] if n['source_script'] == script}:
            raise ValueError('Missing reviewed NPC instance')
    for key, note in spec.get('item_notes', {}).items():
        if key not in result['items'] or not isinstance(note, str):
            raise ValueError('Invalid item limitation note')
        result['items'][key]['description'] += '\n' + note
    if spec.get('world'):
        result['world'] = copy.deepcopy(spec['world'])
    for item in result['items'].values():
        item['logout_vanish'] = len(item['raw_columns']) > 78 and item['raw_columns'][78] == '1'
    return result


def merge_quest_module(result, module):
    """Validate into a copy so failed merges never partially mutate the caller."""
    merged = copy.deepcopy(result)
    ids = {n['id'] for n in merged['npcs']}
    for npc in module['npcs']:
        if 'kind' in npc and (module['module_id'] != 'golden-bui' or npc.get('service_id') not in module.get('services', {})):
            raise ValueError('Unreviewed service identity')
        if npc['id'] in ids:
            raise ValueError('Duplicate quest instance: ' + npc['id'])
        ids.add(npc['id'])
        merged['npcs'].append(copy.deepcopy(npc))
    for kind in ('items', 'reward_pets'):
        for key, value in module[kind].items():
            if key in merged[kind]:
                # Shared original definitions may have an existing user-facing
                # limitation or runtime equipment annotation; never overwrite.
                old = merged[kind][key]
                identity = ('raw_columns',) if kind == 'items' else ('enemy_id', 'template_id', 'level', 'sprite', 'weights')
                if any(old.get(field) != value.get(field) for field in identity):
                    raise ValueError('Conflicting quest definition: ' + kind + '/' + key)
            else:
                merged[kind][key] = copy.deepcopy(value)
    for job in module['jobs']:
        old = next((j for j in merged['jobs'] if j['id'] == job['id']), None)
        if old is not None and old != job:
            raise ValueError('Conflicting quest journal')
        if old is None:
            merged['jobs'].append(copy.deepcopy(job))
    if module.get('drops'):
        entries = module['drops']
        for entry in entries:
            if (entry['source'] != 'gmsv/data/enemy.txt' or type(entry['enemy_id']) is not int
                    or type(entry['item_id']) is not int or not 0 <= entry['probability'] <= 1000
                    or str(entry['item_id']) not in module['items'] or not entry.get('audit')):
                raise ValueError('Invalid reviewed quest drop')
        merged.setdefault('reviewed_drops', {})[module['module_id']] = dict(
            active=bool(module.get('enabled_events')), entries=copy.deepcopy(entries))
    if 'services' in module:
        if module['module_id'] != 'golden-bui':
            raise ValueError('Unreviewed private service module')
        merged.setdefault('server_catalogs', {})['golden-bui'] = {'services': copy.deepcopy(module['services'])}
    modules = merged['provenance'].setdefault('modules', {})
    if module['module_id'] in modules:
        raise ValueError('Duplicate quest module')
    modules[module['module_id']] = copy.deepcopy(module['provenance'])
    return merged


def registered_quest_modules(reference, registry=REGISTRY):
    configuration = json.loads(Path(registry).read_text())
    if configuration.get('version') != 1 or not isinstance(configuration.get('modules'), list):
        raise ValueError('Invalid quest module registry')
    entries = configuration['modules']
    root = Path(__file__).resolve().parents[1]
    for entry in entries:
        if 'builder' in entry:
            if entry['id'] != 'golden-bui' or entry['builder'] != 'golden-bui':
                raise ValueError('Unreviewed quest builder')
            from import_golden_bui import build
            module = build(Path(reference))
            for npc in module['npcs']:
                if 'kind' in npc and npc['kind'] not in ('golden_bui_quiz', 'golden_bui_janken', 'golden_bui_gate'):
                    raise ValueError('Unreviewed service kind')
        else:
            relative = Path(entry['manifest'])
            if relative.is_absolute() or '..' in relative.parts or relative.parts[:1] != ('tools',):
                raise ValueError('Invalid quest manifest path')
            module = load_quest_module(reference, root / relative)
        if module['module_id'] != entry['id']:
            raise ValueError('Quest module identity mismatch')
        declared = {e for npc in module['npcs'] for e in npc['events']}
        enabled = entry['enabled_events']
        if not isinstance(enabled, list) or any(type(e) is not int for e in enabled) or not set(enabled) <= declared:
            raise ValueError('Module activates undeclared events')
        module["enabled_events"] = list(enabled)
        yield module


def extend_registered_modules(reference, result, registry=REGISTRY):
    for module in registered_quest_modules(reference, registry):
        result = merge_quest_module(result, module)
    return result


def module_world_reviews(reference, registry=REGISTRY):
    return [copy.deepcopy(module['world']) for module in registered_quest_modules(reference, registry)
            if module.get('world')]


def apply_module_portal_choices(portals, reviews):
    """Select only an existing source destination at explicitly audited cells."""
    choices = {}
    for review in reviews:
        for choice in review.get('portal_choices', []):
            key = (choice['from_map'], *choice['cell'])
            value = (choice['to_map'], *choice['to_cell'])
            if key in choices and choices[key] != value:
                raise ValueError('Conflicting reviewed module portal choices')
            if not choice.get('source') or not choice.get('reason'):
                raise ValueError('Missing portal choice evidence')
            choices[key] = value
    seen = set()
    result = []
    for portal in portals:
        key = (portal['from_map'], *portal['cell'])
        if key in choices:
            if (portal['to_map'], *portal['target']) != choices[key]:
                continue
            seen.add(key)
        result.append(copy.deepcopy(portal))
    if seen != set(choices):
        raise ValueError('Reviewed portal destination not present in source')
    return result
