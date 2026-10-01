"""Pack imported per-frame PNGs into one sprite sheet per animated sprite.

Several importers write frames one PNG per bitmap into a shared folder and
register them in a manifest with `characters` (animations by sprite id) and
`images` (draw offsets by bitmap):

  battle      client/assets/legacy/battle/manifest.json, battle/images
              (import_battle, import_characters, import_pets, import_mirror,
              import_encounter_art)
  characters  client/assets/legacy/characters/catalog.json, images
              (import_characters: the player characters' walking art; the
              folder is shared with map tiles and props)

Run this once they are done (scripts/setup-original-data.sh does). Each
sprite's frames go into <folder>/sheets/<sprite>.png (tools/sprite_sheets.py),
the manifest gets `sheets`, and the packed per-frame PNGs are deleted, so
Godot imports a few hundred files instead of tens of thousands. A PNG a map
still names (a villager drawn in a player character's frames) is kept. See
docs/technical/sprite-sheets.md.

The battle manifest's `extra_sprites` (pet sprites import_encounter_art.py
keeps in battle/pets/<sprite>.json) are packed the same way; each file gets
its own `sheets`.

Last, the manifests are split into the small per-sprite files the game reads
(split_manifests.py).

Re-running is safe: a frame whose PNG is gone is cut back out of the sheet
that holds it (the sheets are lossless), so running one importer again and
then this tool repacks everything. With --sprites, only the named sheets
are packed; unrelated sheets and their import sidecars remain untouched.
"""
import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

from sprite_sheets import save_sheets
from map_file import load_map
from split_manifests import split

LEGACY = Path(__file__).resolve().parents[1] / 'client/assets/legacy'
# target: (manifest, frame folder, globs of manifests whose `images` also draw from the folder)
TARGETS = {'battle': ('battle/manifest.json', 'battle/images', []),
           'characters': ('characters/catalog.json', 'images', ['*.json', 'world/*.json', 'world/*.map'])}


def referenced(legacy, patterns):
    """Bitmaps other manifests (maps) name in their `images`; their PNGs stay."""
    kept = set()
    for pattern in patterns:
        for path in legacy.glob(pattern):
            try:
                data = load_map(path, header_only=True)
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(data, dict) and isinstance(data.get('images'), dict):
                kept |= {str(k) for k in data['images']}
    return kept


def groups(manifest):
    """Sprite id -> the bitmaps its animations draw, in id order."""
    result = {}
    for sprite, animations in manifest.get('characters', {}).items():
        used = {int(f['image']) for a in animations.values() for f in a['frames']}
        result[str(sprite)] = sorted(b for b in used if str(b) in manifest.get('images', {}))
    return result


def extra_manifests(folder, manifest):
    """(path, data) of each extra sprite file the manifest lists."""
    return [(folder / name, json.loads((folder / name).read_text())) for name in manifest.get('extra_sprites', {}).values()]


def frame_source(folder, images, manifest, extras=()):
    """Loads a bitmap from its PNG, or from the existing sheet holding it."""
    sheets = dict(manifest.get('sheets', {}))
    for _path, data in extras:
        sheets.update(data.get('sheets', {}))
    owners = {b: key for key, sheet in sheets.items() for b in sheet.get('frames', {})}
    opened = {}

    def load(bitmap):
        png = images / f'{bitmap}.png'
        if png.exists():
            with Image.open(png) as image:
                return image.convert('RGBA')
        key = owners.get(str(bitmap))
        if key is None:
            raise FileNotFoundError(f'Bitmap {bitmap} has neither a PNG nor a sheet')
        sheet_index, x, y, w, h = sheets[key]['frames'][str(bitmap)]
        name = sheets[key]['files'][sheet_index]
        if name not in opened:
            with Image.open(folder / name) as image:
                opened[name] = image.convert('RGBA')
        return opened[name].crop((x, y, x + w, y + h))
    return load


def pack(manifest_path, images, keep=frozenset(), sprites=None):
    manifest_path, images = Path(manifest_path), Path(images)
    folder = manifest_path.parent
    manifest = json.loads(manifest_path.read_text())
    extras = extra_manifests(folder, manifest)
    selected = {str(sprite) for sprite in sprites} if sprites is not None else None
    if selected is not None:
        known = set(manifest.get('characters', {}))
        for _, data in extras:
            known.update(data.get('characters', {}))
        if selected - known:
            raise ValueError('Unknown sprites: ' + ', '.join(sorted(selected - known)))
    load = frame_source(folder, images, manifest, extras)
    staging = folder / 'sheets.new'
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir()

    def pack_all(data):
        result = {}
        for sprite, bitmaps in groups(data).items():
            if not bitmaps or (selected is not None and sprite not in selected):
                continue
            entry = save_sheets({b: load(b) for b in bitmaps}, staging, sprite)
            entry['files'] = ['sheets/' + name for name in entry['files']]
            result[sprite] = entry
        return result
    sheets = pack_all(manifest)
    extra_sheets = [pack_all(data) for _path, data in extras]
    # Swap in the new sheets only once every frame was read from the old ones.
    if selected is None:
        shutil.rmtree(folder / 'sheets', ignore_errors=True)
        staging.rename(folder / 'sheets')
    else:
        # A local refresh must not re-encode any unrelated sheet or discard
        # its Godot import sidecar. Move only the selected sprites' new PNGs.
        destination = folder / 'sheets'
        destination.mkdir(exist_ok=True)
        for path in staging.iterdir():
            path.replace(destination / path.name)
        staging.rmdir()
    manifest['sheets'] = sheets if selected is None else {**manifest.get('sheets', {}), **sheets}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    for (path, data), packed in zip(extras, extra_sheets):
        if selected is not None and not packed:
            continue
        data['sheets'] = packed if selected is None else {**data.get('sheets', {}), **packed}
        path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    everything = [sheets] + extra_sheets
    frames = sum(len(s['frames']) for group in everything for s in group.values())
    files = sum(len(s['files']) for group in everything for s in group.values())
    removed = 0
    for sheet in [s for group in everything for s in group.values()]:
        for bitmap in sheet['frames']:
            png = images / f'{bitmap}.png'
            if bitmap not in keep and png.exists():
                png.unlink()
                Path(str(png) + '.import').unlink(missing_ok=True)
                removed += 1
    if images.is_dir() and not any(images.iterdir()):
        images.rmdir()
    size = sum(p.stat().st_size for p in (folder / 'sheets').glob('*.png'))
    print(f'Packed {frames} frames of {len(sheets)} sprites and {len(extras)} extra sprites into {files} sheets ({size // (1 << 20)} MB) in {folder / "sheets"}; '
          f'removed {removed} frame PNGs' + (f', kept {len(keep & {b for group in everything for s in group.values() for b in s["frames"]})} that maps also draw' if keep else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # Checked by hand: Python 3.9's argparse matches an empty or default list against choices and fails.
    parser.add_argument('targets', nargs='*', help='any of %s (default: all)' % ', '.join(TARGETS))
    parser.add_argument('--sprites', type=int, nargs='+', help='pack only these sprites, preserving unrelated sheets and imports')
    args = parser.parse_args()
    unknown = [t for t in args.targets if t not in TARGETS]
    if unknown:
        parser.error('unknown target: ' + ', '.join(unknown))
    for target in args.targets or list(TARGETS):
        manifest, images, others = TARGETS[target]
        pack(LEGACY / manifest, LEGACY / images, referenced(LEGACY, others), args.sprites)
    # The game reads per-sprite files made from the manifests (split_manifests.py).
    split(args.targets or list(TARGETS), LEGACY)
