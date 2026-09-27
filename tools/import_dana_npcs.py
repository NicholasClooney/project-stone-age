"""Restore reviewed Dana ordinary actors; unsupported services stay explicitly inert.

Original actor positions, text and art stay in ignored local assets. Quest, family
and working-airline scripts are intentionally excluded from this slice.
"""
import argparse
import json
from pathlib import Path
import re
from import_legacy import Archive

MAPS = {5100, 5101, 5103, 5105, 5106}
SOURCES = ('airway.create', 'shop_m3.create', 'shop_nuke1.create', 'sp.create')


def definitions(reference):
    root = Path(reference)/'gmsv/data/npc'
    for name in SOURCES:
        path = root/'genout'/name
        for match in re.finditer(r'\{([^}]+)\}', path.read_text(encoding='gb18030')):
            fields = dict(line.strip().split('=', 1) for line in match[1].splitlines()
                          if '=' in line and not line.lstrip().startswith('#'))
            if int(fields.get('floorid', -1)) not in MAPS:
                continue
            x, y, x2, y2 = map(int, fields['borncorner'].split(','))
            if (x, y) != (x2, y2):
                raise ValueError('Moving Dana NPC needs explicit support')
            script = fields['enemy']
            handler = script.split('|', 1)[0]
            dialogue = root/script.split('file:', 1)[1] if 'file:' in script else None
            text = ''
            lines = []
            if dialogue:
                raw = dialogue.read_text(encoding='gb18030').strip()
                if handler == 'npcgen_man':
                    lines = [line.strip() for line in raw.split(',') if line.strip()]
                    text = lines[0] if lines else ''
                elif handler == 'npcgen_signboard':
                    text = raw.replace('\\n', '\n')
                else:
                    values = dict(line.split(':', 1) for line in raw.splitlines() if ':' in line)
                    text = values.get('main_msg', values.get('buy_main', '')).replace('\\n', '\n').strip()
            role = 'resident' if handler == 'npcgen_man' else 'sign' if handler == 'npcgen_signboard' else 'decoration' if handler == 'npcgen_mugon' else 'deferred_service'
            yield dict(map_id=int(fields['floorid']), cell=[x,y], name=fields['name'],
                       graphic=int(fields['graphicname']), facing=int(fields['dir']), role=role,
                       text=text, dialogues=lines, handler=handler, source=str(path.relative_to(reference)),
                       dialogue_source=str(dialogue.relative_to(reference)) if dialogue else '')


def import_residents(archive, reference, world_root):
    world_root = Path(world_root)
    (world_root/'npcs').mkdir(exist_ok=True)
    logical = {e['map_id']:e['id'] for e in archive.entries.values() if e['map_id']}
    residents = []
    for npc in definitions(Path(reference)):
        graphic = npc['graphic']
        frame = {'x':0, 'y':0}
        if graphic in logical:
            bitmap = logical[graphic]
        else:
            actions = archive.animations(graphic)
            frame = actions[f"3_{npc['facing']}"]['frames'][0]
            bitmap = frame['image']
        entry = archive.entries[bitmap]
        archive.image(bitmap).save(world_root/'npcs'/f'{graphic}.png')
        npc.update(path=f'world/npcs/{graphic}.png',offset=[entry['x']+frame['x'],entry['y']+frame['y']])
        residents.append(npc)
    return residents


def run(source, reference, output):
    root=Path(output);manifest=root/'world/manifest.json'
    data=json.loads(manifest.read_text())
    residents=import_residents(Archive(source),Path(reference),root/'world')
    data['residents']=[npc for npc in data['residents'] if npc['map_id'] not in MAPS]+residents
    manifest.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')))
    print(f'Imported {len(residents)} original Dana actors')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('--reference',default='references/chenmingbiao-stone-age');p.add_argument('--output',default='client/assets/legacy')
    a=p.parse_args();run(a.source,a.reference,a.output)
