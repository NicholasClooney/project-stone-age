"""Split the importers' big art manifests into small runtime files.

The importers keep one manifest per kind of art as their working data. Parsed
by Godot, each frame there is a Dictionary, so the game held about 400 MB for
them (docs/technical/memory-baseline.md). The game reads these files instead,
one small index at startup and one file per sprite when it is drawn
(docs/technical/sprite-sheets.md, "Runtime files"):

  battle/manifest.json + battle/pets/*.json
      -> battle/index.json        shared battle data and the sprite list
         battle/sprites/<id>.json one battle or pet sprite
  riding/manifest.json
      -> riding/index.json        rider and mount pairs, names, frame sounds
         riding/composites/<id>.json
  characters/catalog.json
      -> characters/index.json    the chooser's list
         characters/art/<id>.json one player character's walking art
  battle/backgrounds.json
      -> battle/battlefields.json packed ground -> battlefield lookups

A sprite file is compact:

  {"animations": {"3_0": [duration_ms, image, x, y, sound, image, x, y, sound, ...]},
   "files": ["sheets/100000.png"],
   "bitmaps": [bitmap, x, y, w, h, sheet, sheet_x, sheet_y, ...]}

`bitmaps` has one row of 8 numbers per bitmap the animations draw: its draw
offset and size, then the index into `files` and the frame's position in that
sheet (sheet -1 when it is not packed). A bitmap drawn from another sprite's
sheet (a club variant sharing frames) names that sheet in `files`.

The importer manifests stay where they are for the tools and are not shipped
(tools/plan_web_packs.py skips them). Run after any importer that changes them;
pack_frame_sheets.py, import_riding.py, import_battle_sounds.py and
import_battle_backgrounds.py call it for their own art, and
scripts/setup-original-data.sh runs it last.
"""
import argparse
import base64
import json
import shutil
import struct
from pathlib import Path

LEGACY = Path(__file__).resolve().parents[1] / 'client/assets/legacy'
KINDS = ('battle', 'riding', 'characters', 'backgrounds')
# The actions and directions a battle needs (server/troop_art.gd).
BATTLE_ACTIONS = (0, 1, 2, 3, 4, 10)
BATTLE_SHARED = ('player_id', 'enemy_id', 'enemy_name', 'equipment_variants', 'ui', 'audio',
                 'frame_sounds', 'background', 'provenance')
RIDING_SHARED = ('pairs', 'names', 'unavailable', 'source', 'certificate_source', 'extra_source',
                 'frame_sounds', 'provenance')
CHARACTER_SHARED = ('choices', 'skipped', 'provenance')


def dump(data) -> str:
    return json.dumps(data, ensure_ascii=False, separators=(',', ':'))


def owners(sheets: dict) -> dict:
    """Bitmap -> sheet key; each bitmap is in one sheet per folder."""
    return {str(b): key for key, sheet in sheets.items() for b in sheet.get('frames', {})}


def sprite_file(key: str, animations: dict, images: dict, sheets: dict, owner: dict) -> dict:
    """One sprite's compact file (see the module docstring)."""
    compact = {}
    used = []
    seen = set()
    for name, animation in animations.items():
        row = [int(animation['duration_ms'])]
        for frame in animation['frames']:
            image = int(frame['image'])
            row += [image, int(frame.get('x', 0)), int(frame.get('y', 0)), int(frame.get('sound', 0))]
            if image not in seen:
                seen.add(image)
                used.append(image)
        compact[name] = row
    files = []
    bitmaps = []
    for image in used:
        info = images.get(str(image))
        if info is None:
            continue
        spot_key = key if str(image) in sheets.get(key, {}).get('frames', {}) else owner.get(str(image))
        sheet, sx, sy = -1, 0, 0
        if spot_key is not None:
            entry = sheets[spot_key]
            spot = entry['frames'][str(image)]
            name = entry['files'][int(spot[0])]
            if name not in files:
                files.append(name)
            sheet, sx, sy = files.index(name), int(spot[1]), int(spot[2])
        bitmaps += [image, int(info['x']), int(info['y']), int(info['w']), int(info['h']), sheet, sx, sy]
    return {'animations': compact, 'files': files, 'bitmaps': bitmaps}


def renderable(key: str, animations: dict, images: dict, sheets: dict):
    """The sheet files a battle needs for this sprite, or False when the
    sprite cannot fight: an action or direction without frames, a frame
    without its image, or one missing from the sprite's own sheet. Same
    rules as server/troop_art.gd before the split."""
    own = sheets.get(key, {})
    needed = []
    for action in BATTLE_ACTIONS:
        for direction in range(8):
            frames = animations.get(f'{action}_{direction}', {}).get('frames', [])
            if not frames:
                return False
            for frame in frames:
                bitmap = str(int(frame['image']))
                spot = own.get('frames', {}).get(bitmap)
                if bitmap not in images or spot is None or len(spot) < 5:
                    return False
                name = own['files'][int(spot[0])]
                if name not in needed:
                    needed.append(name)
    return needed


def write_folder(folder: Path, files: dict) -> None:
    """Replaces folder with exactly these files (name -> text), atomically enough
    that an interrupted run leaves the old folder in place."""
    staging = folder.with_name(folder.name + '.new')
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    for name, text in files.items():
        (staging / name).write_text(text)
    shutil.rmtree(folder, ignore_errors=True)
    staging.rename(folder)


def split_battle(legacy: Path = LEGACY) -> None:
    root = legacy / 'battle'
    source = root / 'manifest.json'
    if not source.exists():
        return
    manifest = json.loads(source.read_text())
    sheets = dict(manifest.get('sheets', {}))
    extras = {}
    for ident, name in manifest.get('extra_sprites', {}).items():
        path = root / name
        if path.exists():
            extras[str(ident)] = json.loads(path.read_text())
            sheets.update(extras[str(ident)].get('sheets', {}))
    owner = owners(sheets)
    files = {}
    index = {key: manifest[key] for key in BATTLE_SHARED if key in manifest}
    index['sprites'] = {}
    index['extra_sprites'] = {}
    for ident, animations in manifest.get('characters', {}).items():
        files[f'{ident}.json'] = dump(sprite_file(ident, animations, manifest.get('images', {}), sheets, owner))
        index['sprites'][ident] = renderable(ident, animations, manifest.get('images', {}), manifest.get('sheets', {}))
    for ident, data in extras.items():
        animations = data.get('characters', {}).get(ident)
        if animations is None or ident in index['sprites']:
            continue
        files[f'{ident}.json'] = dump(sprite_file(ident, animations, data.get('images', {}), sheets, owner))
        index['extra_sprites'][ident] = renderable(ident, animations, data.get('images', {}), data.get('sheets', {}))
    write_folder(root / 'sprites', files)
    (root / 'index.json').write_text(dump(index))
    size = sum(len(text.encode()) for text in files.values())
    print(f'battle: {len(index["sprites"])} sprites and {len(index["extra_sprites"])} pet sprites '
          f'in battle/sprites ({size / 1e6:.1f} MB)')


def split_riding(legacy: Path = LEGACY) -> None:
    root = legacy / 'riding'
    source = root / 'manifest.json'
    if not source.exists():
        return
    manifest = json.loads(source.read_text())
    sheets = manifest.get('sheets', {})
    owner = owners(sheets)
    files = {}
    index = {key: manifest[key] for key in RIDING_SHARED if key in manifest}
    index['composites'] = {}
    for ident, animations in manifest.get('characters', {}).items():
        files[f'{ident}.json'] = dump(sprite_file(ident, animations, manifest.get('images', {}), sheets, owner))
        index['composites'][ident] = True
    write_folder(root / 'composites', files)
    (root / 'index.json').write_text(dump(index))
    size = sum(len(text.encode()) for text in files.values())
    print(f'riding: {len(files)} composites in riding/composites ({size / 1e6:.1f} MB)')


def split_characters(legacy: Path = LEGACY) -> None:
    root = legacy / 'characters'
    source = root / 'catalog.json'
    if not source.exists():
        return
    catalog = json.loads(source.read_text())
    sheets = catalog.get('sheets', {})
    owner = owners(sheets)
    files = {}
    index = {key: catalog[key] for key in CHARACTER_SHARED if key in catalog}
    index['characters'] = {}
    for ident, animations in catalog.get('characters', {}).items():
        files[f'{ident}.json'] = dump(sprite_file(ident, animations, catalog.get('images', {}), sheets, owner))
        index['characters'][ident] = True
    write_folder(root / 'art', files)
    (root / 'index.json').write_text(dump(index))
    print(f'characters: {len(files)} characters in characters/art')


def split_backgrounds(legacy: Path = LEGACY) -> None:
    """ground_to_battlefields becomes a table of the distinct choices plus one
    little-endian uint16 per ground id (0 = not listed: battlefield 0, as the
    original's default), base64 in the JSON; bitmap_to_ground becomes two
    sorted arrays for a binary search."""
    root = legacy / 'battle'
    source = root / 'backgrounds.json'
    if not source.exists():
        return
    catalog = json.loads(source.read_text())
    choices = [[0, 0, 0]]
    table = {}
    grounds = {int(k): [int(x) for x in v] for k, v in catalog.get('ground_to_battlefields', {}).items()}
    size = max(grounds) + 1 if grounds else 0
    column = [0] * size
    for ground, triple in grounds.items():
        if ground < 0:
            continue
        key = tuple(triple)
        if key not in table:
            table[key] = len(choices)
            choices.append(list(key))
        column[ground] = table[key]
    if len(choices) > 0xFFFF:
        raise ValueError('too many battlefield choices for uint16')
    pairs = sorted((int(k), int(v)) for k, v in catalog.get('bitmap_to_ground', {}).items())
    result = {
        'choices': [x for triple in choices for x in triple],
        'ground_choice': base64.b64encode(struct.pack(f'<{size}H', *column)).decode(),
        'bitmaps': [b for b, _g in pairs],
        'grounds': [g for _b, g in pairs],
        'backgrounds': {k: v['path'] for k, v in catalog.get('backgrounds', {}).items()},
        'unavailable': catalog.get('unavailable', {}),
        'provenance': catalog.get('provenance', ''),
    }
    (root / 'battlefields.json').write_text(dump(result))
    print(f'backgrounds: {size} ground ids, {len(choices) - 1} distinct choices, {len(pairs)} bitmaps in battle/battlefields.json')


SPLITTERS = {'battle': split_battle, 'riding': split_riding, 'characters': split_characters,
             'backgrounds': split_backgrounds}


def split(kinds=KINDS, legacy: Path = LEGACY) -> None:
    for kind in kinds:
        SPLITTERS[kind](Path(legacy))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('kinds', nargs='*', help='any of %s (default: all)' % ', '.join(KINDS))
    parser.add_argument('--legacy', default=str(LEGACY), help='the imported asset folder')
    args = parser.parse_args()
    unknown = [k for k in args.kinds if k not in KINDS]
    if unknown:
        parser.error('unknown kind: ' + ', '.join(unknown))
    split(args.kinds or KINDS, Path(args.legacy))
