"""Import original SAB battlefields and server ground-tile selection table."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from PIL import Image
from import_legacy import Archive
from split_manifests import split_backgrounds


def read_mapping(path):
    result = {}
    choices = [0, 0, 0]
    for raw in Path(path).read_text(encoding='latin1').splitlines():
        line = raw.split('#', 1)[0].strip()
        if line.startswith('$'):
            numbers = [int(x) for x in re.findall(r'\d+', line[1:])[:3]]
            if not numbers:
                raise ValueError('Missing battlefield number')
            choices = numbers + [numbers[0]] * (3-len(numbers))
        else:
            match = re.match(r'^(\d+)(?:\s*to\s*(\d+))?', line)
            if match:
                start = int(match[1])
                for tile in range(start, int(match[2] or start)+1):
                    result[str(tile)] = choices.copy()
    return result


def render(archive, raw):
    if raw[:4] != b'SAB ' or len(raw) != 804:
        raise ValueError('Expected original 20x20 SAB terrain')
    tiles = struct.unpack('>400H', raw[4:])
    canvas = Image.new('RGBA', (1280, 960))
    for row in range(20):
        for column in range(20):
            entry = archive.entries[archive.map_ids[tiles[row*20+column]]]
            canvas.alpha_composite(archive.image(entry['id']), (32*(row+column)+entry['x'], 480+24*(row-column)+entry['y']))
    background = canvas.crop((328, 246, 888, 666)).resize((800, 600), Image.Resampling.NEAREST)
    if background.getextrema()[3][0] != 255:
        raise ValueError('Uncovered terrain in battlefield crop')
    return background


def run(source, mapping, output):
    archive = Archive(source)
    output = Path(output)
    (output/'backgrounds').mkdir(parents=True, exist_ok=True)
    table = read_mapping(mapping)
    backgrounds, unavailable = {}, {}
    for path in sorted((archive.data/'battleMap').glob('battle*.sab')):
        ident = str(int(path.stem.removeprefix('battle')))
        raw = path.read_bytes()
        try:
            render(archive, raw).save(output/'backgrounds'/f'{ident}.png')
            backgrounds[ident] = dict(path=f'backgrounds/{ident}.png', sha256=hashlib.sha256(raw).hexdigest())
        except (ValueError, KeyError) as error:
            unavailable[ident] = str(error)
    metadata = dict(ground_to_battlefields=table, bitmap_to_ground={str(e['id']):e['map_id'] for e in archive.entries.values() if e['map_id']}, backgrounds=backgrounds, unavailable=unavailable,
        provenance='battle.c BATTLE_getBattleFieldNo: encounter ground tile -> MAP_BATTLEMAP[1..3], RAND(0,2); readmap.c MAP_readBattleMapConfFile; original 2.5 battleMap SAB terrain',
        mapping_sha256=hashlib.sha256(Path(mapping).read_bytes()).hexdigest())
    (output/'backgrounds.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n')
    print(f'Imported {len(backgrounds)} original battlefields; unavailable={unavailable}; mapped {len(table)} ground tiles')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--mapping', default='references/chenmingbiao-stone-age/gmsv/data/map/battlemap.txt')
    parser.add_argument('--output', default='client/assets/legacy/battle')
    args = parser.parse_args()
    run(args.source, args.mapping, args.output)
    # The game reads the packed lookups (split_manifests.py).
    split_backgrounds(Path(args.output).parent)
