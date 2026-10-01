"""Import the 48 classic player appearances and source-verified club and axe variants.
Run after import_battle.py; local original resources stay ignored.
"""
import argparse
import json
import re
from pathlib import Path
from import_legacy import Archive
from import_battle import animations


def equipment_rows(source_root, weapon="club"):
    root = Path(source_root)
    constants = dict((name, int(number)) for name, number in re.findall(
        r'#define\s+(SPR_\d{3}(?:em|cl|ax))\s+(\d+)',
        (root / 'include/anim_tbl.h').read_text(errors='replace')))
    source = (root / 'char/char_data.c').read_text(errors='replace')
    table = source.split('int CHAR_eqimagetbl[][5]=', 1)[1].split('};', 1)[0]
    result = {}
    for empty, axe, club in re.findall(r'\{\s*(SPR_\d{3}em)\s*,\s*(SPR_\d{3}ax)\s*,\s*(SPR_\d{3}cl)', table):
        base = constants[empty]
        if 100000 <= base <= 100235:
            result[str(base)] = str(constants[axe if weapon == "axe" else club])
    if len(result) != 48:
        raise ValueError(f'Expected 48 verified classic appearances, found {len(result)}')
    return dict(sorted(result.items(), key=lambda row: int(row[0])))


def run(source, reference, output):
    output = Path(output)
    archive = Archive(source)
    rows = equipment_rows(reference)
    axe_rows = equipment_rows(reference, "axe")
    battle_path = output / 'battle/manifest.json'
    battle = json.loads(battle_path.read_text())
    field_characters, metadata, choices, skipped, axe_skipped = {}, {}, [], [], []
    (output / 'characters').mkdir(parents=True, exist_ok=True)
    for base, club in rows.items():
        axe = axe_rows[base]
        try:
            field = archive.animations(int(base))
            battle_actions = {ident: animations(archive, int(ident)) for ident in (base, club)}
            used = {frame['image'] for actions in [field, *battle_actions.values()] for sequence in actions.values() for frame in sequence['frames']}
            for bitmap in used:
                archive.image(bitmap)
        except (ValueError, KeyError) as error:
            skipped.append(dict(id=base, reason=str(error)))
            print(f'Skipped {base}: {error}', flush=True)
            continue
        # A missing weapon clip must not remove an otherwise valid appearance.
        try:
            axe_actions = animations(archive, int(axe))
            for sequence in axe_actions.values():
                for frame in sequence['frames']:
                    archive.image(frame['image'])
            battle_actions[axe] = axe_actions
        except (ValueError, KeyError) as error:
            axe_skipped.append(dict(id=base, axe=axe, reason=str(error)))
            print(f'Skipped axe {base}: {error}', flush=True)
        for direction in range(8):
            for action in (3, 4):
                if not field.get(f'{action}_{direction}', {}).get('frames'):
                    raise ValueError(f'{base} missing idle/walk direction {direction}')
        field_characters[base] = field
        choices.append(dict(id=base, family=(int(base)-100000)//20+1, palette=((int(base)-100000)%20)//5+1, club=club))
        if axe in battle_actions:
            choices[-1]["axe"] = axe
        for sequence in field.values():
            for frame in sequence['frames']:
                bitmap = frame['image']
                if str(bitmap) not in metadata:
                    archive.image(bitmap).save(output / 'images' / f'{bitmap}.png')
                    metadata[str(bitmap)] = {k:archive.entries[bitmap][k] for k in ('x','y','w','h','ex','ey','hit','priority')}
        for ident in battle_actions:
            actions = battle_actions[ident]
            battle['characters'][ident] = actions
            for sequence in actions.values():
                for frame in sequence['frames']:
                    bitmap = frame['image']
                    if str(bitmap) not in battle['images']:
                        (output / 'battle/images').mkdir(parents=True, exist_ok=True)
                        archive.image(bitmap).save(output / 'battle/images' / f'{bitmap}.png')
                        battle['images'][str(bitmap)] = {k:archive.entries[bitmap][k] for k in ('x','y','w','h')}
    battle['equipment_variants']['club'].update({choice['id']: choice['club'] for choice in choices})
    battle['equipment_variants']['axe'] = {choice['id']: choice['axe'] for choice in choices if 'axe' in choice}
    battle['provenance']['character_selection'] = 'gmsv/char/char_data.c CHAR_eqimagetbl paired with include/anim_tbl.h; 48 classic appearances, each idle/walk eight directions verified in local pack'
    battle_path.write_text(json.dumps(battle, ensure_ascii=False, indent=2)+'\n')
    manifest = dict(choices=choices, skipped=skipped, axe_skipped=axe_skipped, characters=field_characters, images=metadata,
                    provenance='Original 2.5 SPR/ADRN; classic appearance IDs and club/axe lookup from pinned gmsv CHAR_eqimagetbl')
    (output/'characters/catalog.json').write_text(json.dumps(manifest, ensure_ascii=False)+'\n')
    print(f'Imported {len(choices)} original appearances, {len(metadata)} field images and verified club/axe battle variants')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--reference', default='references/chenmingbiao-stone-age/gmsv')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.reference, args.output)
