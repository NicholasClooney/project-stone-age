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

Re-running is safe: a frame whose PNG is gone is cut back out of the sheet
that holds it (the sheets are lossless), so running one importer again and
then this tool repacks everything.
"""
import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

from sprite_sheets import save_sheets

LEGACY = Path(__file__).resolve().parents[1] / 'client/assets/legacy'
# target: (manifest, frame folder, globs of manifests whose `images` also draw from the folder)
TARGETS = {'battle': ('battle/manifest.json', 'battle/images', []),
           'characters': ('characters/catalog.json', 'images', ['*.json', 'world/*.json'])}


def referenced(legacy, patterns):
    """Bitmaps other manifests (maps) name in their `images`; their PNGs stay."""
    kept = set()
    for pattern in patterns:
        for path in legacy.glob(pattern):
            try:
                data = json.loads(path.read_text())
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


def frame_source(folder, images, manifest):
    """Loads a bitmap from its PNG, or from the existing sheet holding it."""
    owners = {b: key for key, sheet in manifest.get('sheets', {}).items() for b in sheet.get('frames', {})}
    opened = {}

    def load(bitmap):
        png = images / f'{bitmap}.png'
        if png.exists():
            with Image.open(png) as image:
                return image.convert('RGBA')
        key = owners.get(str(bitmap))
        if key is None:
            raise FileNotFoundError(f'Bitmap {bitmap} has neither a PNG nor a sheet')
        sheet_index, x, y, w, h = manifest['sheets'][key]['frames'][str(bitmap)]
        name = manifest['sheets'][key]['files'][sheet_index]
        if name not in opened:
            with Image.open(folder / name) as image:
                opened[name] = image.convert('RGBA')
        return opened[name].crop((x, y, x + w, y + h))
    return load


def pack(manifest_path, images, keep=frozenset()):
    manifest_path, images = Path(manifest_path), Path(images)
    folder = manifest_path.parent
    manifest = json.loads(manifest_path.read_text())
    load = frame_source(folder, images, manifest)
    staging = folder / 'sheets.new'
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir()
    sheets = {}
    for sprite, bitmaps in groups(manifest).items():
        if not bitmaps:
            continue
        entry = save_sheets({b: load(b) for b in bitmaps}, staging, sprite)
        entry['files'] = ['sheets/' + name for name in entry['files']]
        sheets[sprite] = entry
    # Swap in the new sheets only once every frame was read from the old ones.
    shutil.rmtree(folder / 'sheets', ignore_errors=True)
    staging.rename(folder / 'sheets')
    manifest['sheets'] = sheets
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    frames = sum(len(s['frames']) for s in sheets.values())
    files = sum(len(s['files']) for s in sheets.values())
    removed = 0
    for sheet in sheets.values():
        for bitmap in sheet['frames']:
            png = images / f'{bitmap}.png'
            if bitmap not in keep and png.exists():
                png.unlink()
                Path(str(png) + '.import').unlink(missing_ok=True)
                removed += 1
    if images.is_dir() and not any(images.iterdir()):
        images.rmdir()
    size = sum(p.stat().st_size for p in (folder / 'sheets').glob('*.png'))
    print(f'Packed {frames} frames of {len(sheets)} sprites into {files} sheets ({size // (1 << 20)} MB) in {folder / "sheets"}; '
          f'removed {removed} frame PNGs' + (f', kept {len(keep & {b for s in sheets.values() for b in s["frames"]})} that maps also draw' if keep else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # Checked by hand: Python 3.9's argparse matches an empty or default list against choices and fails.
    parser.add_argument('targets', nargs='*', help='any of %s (default: all)' % ', '.join(TARGETS))
    args = parser.parse_args()
    unknown = [t for t in args.targets if t not in TARGETS]
    if unknown:
        parser.error('unknown target: ' + ', '.join(unknown))
    for target in args.targets or list(TARGETS):
        manifest, images, others = TARGETS[target]
        pack(LEGACY / manifest, LEGACY / images, referenced(LEGACY, others))
