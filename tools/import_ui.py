"""Extract classic UI art and palette-derived automap colors from local resources."""
import argparse
import json
import shutil
import struct
from pathlib import Path
from import_legacy import Archive

# Logical graphic numbers, resolved through ADRN.attr.bmpnumber (offset 76).
IDS = [26012,26042,26081,26236,26260,26101,26102,26103,26104,26105,26106,
       26234,26235,26237,26238,26111,26112,26113,26114,26248,26249,
       26115,26116,26119,26120,26091,25610] + list(range(26001,26010)) + list(range(26150,26164)) + list(range(25600,25610))
# SPR_leader (anim_tbl.h): the flag over a 组队 leader's head (character.cpp).
LEADER_SPRITE = 100500

def sprite_sequence(archive, sprite):
    """(duration_ms, bitmap ids) of a one-action sprite, in play order."""
    index, raw = archive.sprite_bytes()
    for offset in range(0, len(index), 12):
        number, at, count = struct.unpack_from('<IIH', index, offset)
        if number == sprite:
            break
    else:
        raise ValueError(f'Missing sprite {sprite}')
    _direction, _action, duration, frames = struct.unpack_from('<HHII', raw, at)
    at += 12
    if frames > 1000:
        raise ValueError('Unreasonable frame count')
    return duration, [struct.unpack_from('<IhhH', raw, at + i * 10)[0] for i in range(frames)]

def run(source, output):
    archive = Archive(source)
    output = Path(output)
    folder = output / 'ui'
    folder.mkdir(parents=True, exist_ok=True)
    # UI uses full logical IDs; map tile storage alone is 16-bit.
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    metadata = {}
    for number in IDS:
        ident = logical[number]
        archive.image(ident).save(folder / f'{number}.png')
        metadata[str(number)] = dict(bitmap=ident, width=archive.entries[ident]['w'], height=archive.entries[ident]['h'])
    # The leader flag's frames are UI images 25600..25609; the manifest keeps
    # its play order by logical number.
    duration, bitmaps = sprite_sequence(archive, LEADER_SPRITE)
    number_of = {e['id']: e['map_id'] for e in archive.entries.values() if e['map_id']}
    leader_mark = dict(sprite=LEADER_SPRITE, duration_ms=duration, frames=[number_of[b] for b in bitmaps])
    world = json.loads((output / 'samgir.json').read_text())
    colors = {}
    # Original getAutoMapColor averages non-transparent pixels then finds nearest SAP entry.
    for entry in world['ground'] + world['objects']:
        ident = int(entry[2])
        if str(ident) in colors:
            continue
        pixels = [pixel[:3] for pixel in archive.image(ident).getdata() if pixel[3]]
        mean = [sum(p[channel] for p in pixels)//len(pixels) for channel in range(3)] if pixels else [0,0,0]
        palette_index = min([0]+list(range(16,240)), key=lambda i: sum((archive.palette[i][c]-mean[c])**2 for c in range(3)))
        colors[str(ident)] = list(archive.palette[palette_index])
    (folder / 'manifest.json').write_text(json.dumps(dict(images=metadata, map_colors=colors, leader_mark=leader_mark), indent=2)+'\n')
    for name in ('sas_02.wav','sas_03.wav'):
        shutil.copyfile(Path(source)/'data/se'/name,output/name)
    print(f'Imported {len(metadata)} original UI images and {len(colors)} automap colors')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('--output',default='client/assets/legacy')
    args=parser.parse_args()
    run(args.source,args.output)
