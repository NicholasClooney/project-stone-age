"""Import original priority pets; explicit template IDs avoid newbie/boss duplicates."""
import argparse
import csv
import json
from pathlib import Path
from import_legacy import Archive
from import_battle import animations

PETS = {'blue_dragon': (92, '蓝人龙', '人龙'),
        'golden_tiger': (194, '金虎', '老虎'),
        'red_rex': (303, '红暴龙', '暴龙')}


def templates(path):
    result = {}
    for row in csv.reader(Path(path).read_bytes().decode('gb18030', errors='replace').splitlines()):
        if len(row) > 38 and row[6].strip().isdigit():
            result[int(row[6])] = row
    return result


def run(source, reference, output):
    archive = Archive(source)
    output = Path(output)
    records = templates(Path(reference)/'data/enemybase.txt')
    path = output/'battle/manifest.json'
    battle = json.loads(path.read_text())
    catalog = {}
    for key, (ident, alias, group) in PETS.items():
        row = records[ident]
        sprite = int(row[36])
        actions = animations(archive, sprite)
        for direction in range(8):
            for action in (0, 1, 2, 3, 4, 10):
                if not actions.get(f'{action}_{direction}', {}).get('frames'):
                    raise ValueError(f'{key} lacks {action}_{direction}')
        used = {f['image'] for a in actions.values() for f in a['frames']}
        for bitmap in used: archive.image(bitmap)
        for bitmap in used:
            archive.image(bitmap).save(output/'battle/images'/f'{bitmap}.png')
            battle['images'][str(bitmap)] = {k:archive.entries[bitmap][k] for k in ('x','y','w','h')}
        battle['characters'][str(sprite)] = actions
        catalog[key] = dict(name=row[0], alias=alias, category=group, template_id=ident,
                            sprite=sprite, initial=int(row[7]), growth=float(row[8]),
                            weights=[int(x) for x in row[9:13]], elements=[int(x) for x in row[15:19]])
    battle['provenance']['priority_pets'] = 'Pinned gmsv enemybase.txt IDs92/194/303; original SPR clips, all8directions verified. No boss/newbie template substitution.'
    path.write_text(json.dumps(battle, ensure_ascii=False, indent=2)+'\n')
    (output/'pets').mkdir(exist_ok=True)
    (output/'pets/catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
    print('Imported original blue dragon, gold tiger and red rex')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--reference', default='references/chenmingbiao-stone-age/gmsv')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.reference, args.output)
