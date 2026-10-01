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

SPEC = Path(__file__).with_name('early_quest_sources.json')


def source_text(reference, relative, spec):
    raw = (Path(reference) / relative).read_bytes()
    if hashlib.sha256(raw).hexdigest() != spec['sources'][relative]:
        raise ValueError(f'Unreviewed source change: {relative}')
    return raw.decode('gb18030')


def parse_script(text):
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
                if not re.fullmatch(r'(?:ENDEV|NOWEV|ITEM|SP|LV)(?:!=|=|>|<)\d+(?:\*\d+)?', clause):
                    raise ValueError(f'Unsupported predicate: {clause}')
            texts = {k: v.replace('\\n', '\n') for k, v in current.items() if 'Msg' in k}
            actions = {k: v for k, v in current.items() if k not in required and 'Msg' not in k}
            if not actions.keys() <= {'GetItem', 'DelItem', 'GetStone', 'EndSetFlg', 'CleanFlg'}:
                raise ValueError('Unsupported quest action')
            branches.append(dict(event=int(current['EventNo']), type=current['TYPE'], condition=current['EVENT'], texts=texts, actions=actions))
            current = None
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
        if ident not in spec['scripts']:
            raise ValueError(f'Unreviewed NPC: {ident}')
        x, y, x2, y2 = map(int, fields['borncorner'].split(','))
        if (x, y) != (x2, y2) or fields['createnum'] != '1':
            raise ValueError('Unsupported moving/multiple NPC')
        default, branches = parse_script(texts['gmsv/data/npc/' + ident])
        events = spec['script_events'][ident]
        for branch in branches:
            # Keep unrelated key-repair dialogue as provenance, never activate it.
            item_ids = {int(i) for i in re.findall(r'ITEM(?:!=|=)(\d+)', branch['condition'])}
            for key in ('GetItem', 'DelItem'):
                item_ids.update(int(i.split('*')[0]) for i in branch['actions'].get(key, '').split(',') if i)
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
    return dict(version=1, items=items, npcs=npcs, jobs=jobs, provenance=dict(reference_revision=spec['reference_revision'], sources=spec['sources'], client='StoneAge 2.5; logical static graphics, no fallback'))


def run(source, reference, output):
    spec = json.loads(SPEC.read_text())
    result = catalog(reference, spec)
    for relative, expected in spec['client_sources'].items():
        if hashlib.sha256((Path(source)/relative).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Unreviewed client source change: {relative}')
    archive = Archive(source)
    result["provenance"]["client_sources"] = {
        "data/adrn_15.bin": hashlib.sha256((Path(source)/"data/adrn_15.bin").read_bytes()).hexdigest()}
    root = Path(output)
    # Validate all graphics before writing any catalog or art.
    graphics = [n['graphic'] for n in result['npcs']] + [i['logical_icon'] for i in result['items'].values()]
    if any(g not in archive.map_ids for g in graphics):
        raise ValueError('Reviewed static graphics missing from 2.5 client')
    for npc in result['npcs']:
        bitmap = archive.map_ids[npc['graphic']]
        entry = archive.entries[bitmap]
        npc.update(path=f"quests/npcs/{npc['id'].replace('/', '-')}.png", offset=[entry['x'], entry['y']], bitmap_id=bitmap)
        target = root/npc['path']; target.parent.mkdir(parents=True, exist_ok=True)
        archive.image(bitmap).save(target)
    for item in result['items'].values():
        bitmap = archive.map_ids[item['logical_icon']]
        item.update(bitmap_id=bitmap, icon_path=f"quests/items/{item['id']}.png")
        target = root/item['icon_path']; target.parent.mkdir(parents=True, exist_ok=True)
        archive.image(bitmap).save(target)
    target = root/'quests/catalog.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(f"Imported {len(result['npcs'])} reviewed quest NPCs and {len(result['items'])} items")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--reference', default='references/chenmingbiao-stone-age')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.reference, args.output)
