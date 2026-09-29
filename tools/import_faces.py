"""Import the classic character faces (人物面部) and the pet disobedience words.

Faces: the original client builds a character's face graphic number as
    CG_CHR_MAKE_FACE (30000) + family * 100 + colour * 25 + eye * 5 + mouth
(login.cpp:3401-3404, anim_tbl.h:1999), where the family and colour are those
of its appearance (selectGraNoTbl SPR_001em + colour * 5, so appearance id
100000 + family * 20 + colour * 5) and eye and mouth run 0..4. The status
window draws pc.faceGraNo at (209, 118) (menu.cpp:11754). All 25 faces of each
of the 48 classic appearances go into one sprite sheet per appearance,
faces/sheets/<appearance>.png, recorded in faces/manifest.json.

Words: battle.c sends BX (CG_ICON_NO 26509, "No!") over a pet that disobeys
and the pet leaving shows CG_ICON_LEAVE 26513 ("Leave!"). They are added to
battle/ui and battle/manifest.json `ui` like the other battle words, so an
existing import gains them without re-running import_battle.py.

Incremental and local: reads the original 2.5 client, writes ignored assets.
"""
import argparse
import json
from pathlib import Path

from import_legacy import Archive
from sprite_sheets import save_sheets

FACE_BASE = 30000
WORDS = (26509, 26513)


def face_base(appearance):
    """The eye 0 / mouth 0 face of a classic appearance id (100000..100235)."""
    offset = int(appearance) - 100000
    if offset < 0 or offset >= 240 or offset % 5:
        raise ValueError(f'{appearance} is not a classic appearance')
    return FACE_BASE + (offset // 20) * 100 + ((offset % 20) // 5) * 25


def run(source, output):
    archive = Archive(source)
    output = Path(output)
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    folder = output / 'faces'
    (folder / 'sheets').mkdir(parents=True, exist_ok=True)
    characters, sheets, images, skipped = {}, {}, {}, []
    for appearance in range(100000, 100240, 5):
        base = face_base(appearance)
        frames = {}
        try:
            for number in range(base, base + 25):
                bitmap = logical[number]
                frames[number] = archive.image(bitmap)
                entry = archive.entries[bitmap]
                images[str(number)] = {k: entry[k] for k in ('x', 'y', 'w', 'h')}
        except (KeyError, ValueError) as error:
            skipped.append(dict(id=str(appearance), reason=str(error)))
            continue
        entry = save_sheets(frames, folder / 'sheets', str(appearance))
        entry['files'] = ['sheets/' + name for name in entry['files']]
        sheets[str(appearance)] = entry
        characters[str(appearance)] = dict(base=base)
    manifest = dict(characters=characters, sheets=sheets, images=images, skipped=skipped,
                    provenance='Original 2.5 ADRN graphic numbers 30000-31199 via ADRN.attr.bmpnumber; '
                               'CG_CHR_MAKE_FACE + family*100 + colour*25 + eye*5 + mouth (client login.cpp:3401)')
    (folder / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False) + '\n')
    battle_path = output / 'battle/manifest.json'
    if battle_path.exists():
        battle = json.loads(battle_path.read_text())
        (output / 'battle/ui').mkdir(parents=True, exist_ok=True)
        for number in WORDS:
            bitmap = logical[number]
            archive.image(bitmap).save(output / 'battle/ui' / f'{number}.png')
            entry = archive.entries[bitmap]
            battle.setdefault('ui', {})[str(number)] = dict(bitmap=bitmap, width=entry['w'], height=entry['h'], x=entry['x'], y=entry['y'])
        battle_path.write_text(json.dumps(battle, ensure_ascii=False) + '\n')
    print(f'Imported the faces of {len(characters)} appearances ({len(images)} faces), skipped {len(skipped)}; battle words {list(WORDS)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.output)
