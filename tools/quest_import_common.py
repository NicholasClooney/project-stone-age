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
    declared = spec['scripts']
    seen = set()
    for create in spec['creates']:
        for ordinal, block in enumerate(re.findall(r'\{([^}]+)\}', texts[create])):
            fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#'))
            match = re.fullmatch(r'changeevent\|file:(\S+)', fields.get('enemy', ''))
            if not match or match[1] not in declared:
                continue
            script = match[1]
            review = declared[script]
            corners = list(map(int, fields['borncorner'].split(',')))
            if len(corners) != 4 or corners[:2] != corners[2:] or fields['createnum'] != '1':
                raise ValueError('Moving/multiple NPC requires a reviewed handler')
            map_id, cell = int(fields['floorid']), corners[:2]
            # Optional instance allowlist uses the same public stable id.
            ident = instance_id(script, map_id, cell)
            if 'instances' in review and ident not in review['instances']:
                continue
            default, branches = parse_script(texts[PREFIX + script], review['branches'])
            events = review['events']
            if not events or any(type(e) is not int or not 0 < e < 192 for e in events):
                raise ValueError('Invalid module events')
            for branch in branches:
                item_ids = {int(i) for i in re.findall(r'ITEM(?:!=|=)(\d+)', branch['condition'])}
                for key in ('GetItem', 'DelItem', 'GetRandItem'):
                    item_ids.update(int(i.split('*')[0]) for i in branch['actions'].get(key, '').split(',') if i)
                if not item_ids <= set(spec['items']):
                    raise ValueError('Unreviewed branch item')
                if 'GetPet' in branch['actions'] and int(branch['actions']['GetPet']) not in spec.get('reward_enemies', []):
                    raise ValueError('Unreviewed reward enemy')
                branch.update(enabled=True, events=list(events), source=script)
            npc = dict(id=ident, source_script=script, source_create=create, source_create_index=ordinal,
                       events=list(events), name=fields['name'], map_id=map_id, cell=cell,
                       graphic=int(fields['graphicname']), facing=int(fields['dir']), role='quest', text=default, branches=branches)
            if ident in seen:
                raise ValueError('Duplicate quest instance: ' + ident)
            seen.add(ident)
            result['npcs'].append(npc)
    if {n['source_script'] for n in result['npcs']} != set(declared):
        raise ValueError('Missing actual create binding for reviewed script')
    for script, review in declared.items():
        if 'instances' in review and set(review['instances']) != {n['id'] for n in result['npcs'] if n['source_script'] == script}:
            raise ValueError('Missing reviewed NPC instance')
    for key, note in spec.get('item_notes', {}).items():
        if key not in result['items'] or not isinstance(note, str):
            raise ValueError('Invalid item limitation note')
        result['items'][key]['description'] += '\n' + note
    for item in result['items'].values():
        item['logout_vanish'] = len(item['raw_columns']) > 78 and item['raw_columns'][78] == '1'
    return result


def merge_quest_module(result, module):
    """Validate into a copy so failed merges never partially mutate the caller."""
    merged = copy.deepcopy(result)
    ids = {n['id'] for n in merged['npcs']}
    for npc in module['npcs']:
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
    modules = merged['provenance'].setdefault('modules', {})
    if module['module_id'] in modules:
        raise ValueError('Duplicate quest module')
    modules[module['module_id']] = copy.deepcopy(module['provenance'])
    return merged


def extend_registered_modules(reference, result, registry=REGISTRY):
    configuration = json.loads(Path(registry).read_text())
    if configuration.get('version') != 1 or not isinstance(configuration.get('modules'), list):
        raise ValueError('Invalid quest module registry')
    entries = configuration['modules']
    root = Path(__file__).resolve().parents[1]
    for entry in entries:
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
        result = merge_quest_module(result, module)
    return result
