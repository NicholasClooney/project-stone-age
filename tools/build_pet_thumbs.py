"""Pre-cut 宠物大全 thumbnails at import time.

Every battle sprite's first standing frame (animation 3, facing 1, else
facing 0; the same frame scripts/pet_thumbnails.gd used to cut at runtime) is
cropped from its sheet, scaled to at most LIMIT pixels and packed into a few
atlas PNGs. The game then shows every picture from these small files instead
of loading (and on the web, downloading) each sprite's whole sheet.

Output: <assets>/thumbs/atlas-<n>.png and <assets>/thumbs/index.json
{"limit": LIMIT, "files": [...], "sprites": {sprite: [file, x, y, w, h]}}.
"""
import argparse
import json
from pathlib import Path

from PIL import Image

LIMIT = 128
ATLAS = 1024
GAP = 1
STAND = 3


def entries(battle):
    """sprite -> {characters, sheets} for the core manifest and the extra pets."""
    manifest = json.loads((battle/'manifest.json').read_text())
    result = {}
    for sprite, animations in manifest['characters'].items():
        result[sprite] = (animations, manifest['sheets'].get(sprite, {}))
    for sprite, relative in manifest.get('extra_sprites', {}).items():
        extra = json.loads((battle/relative).read_text())
        result[sprite] = (extra['characters'].get(sprite, {}), extra['sheets'].get(sprite, {}))
    return result


def standing_frame(animations):
    animation = animations.get(f'{STAND}_1') or animations.get(f'{STAND}_0') or {}
    frames = animation.get('frames', [])
    return int(frames[0]['image']) if frames else None


def picture(battle, sheets, image, cache):
    spot = sheets.get('frames', {}).get(str(image))
    if not spot:
        return None
    file_index, x, y, w, h = spot
    files = sheets.get('files', [])
    if file_index >= len(files):
        return None
    path = battle/files[file_index]
    if path not in cache:
        cache.clear()
        cache[path] = Image.open(path).convert('RGBA')
    crop = cache[path].crop((x, y, x+w, y+h))
    longest = max(crop.width, crop.height)
    if longest > LIMIT:
        scale = LIMIT/longest
        crop = crop.resize((max(1, int(crop.width*scale)), max(1, int(crop.height*scale))), Image.LANCZOS)
    return crop


def pack(pictures):
    """Shelf-packs pictures into ATLAS x ATLAS sheets: [(sheet, {sprite: (x, y, w, h)})]."""
    sheets = []
    order = sorted(pictures, key=lambda sprite: (-pictures[sprite].height, int(sprite)))
    atlas, places, x, y, shelf = None, {}, 0, 0, 0
    for sprite in order:
        image = pictures[sprite]
        if atlas is None:
            atlas, places, x, y, shelf = Image.new('RGBA', (ATLAS, ATLAS)), {}, 0, 0, 0
        if x+image.width > ATLAS:
            x, y, shelf = 0, y+shelf+GAP, 0
        if y+image.height > ATLAS:
            sheets.append((atlas, places))
            atlas, places, x, y, shelf = Image.new('RGBA', (ATLAS, ATLAS)), {}, 0, 0, 0
        atlas.paste(image, (x, y))
        places[sprite] = (x, y, image.width, image.height)
        x += image.width+GAP
        shelf = max(shelf, image.height)
    if atlas is not None:
        sheets.append((atlas, places))
    return sheets


def build(assets):
    battle = assets/'battle'
    pictures = {}
    cache = {}
    for sprite, (animations, sheets) in sorted(entries(battle).items(), key=lambda item: item[1][1].get('files', [''])[0]):
        image = standing_frame(animations)
        if image is None:
            continue
        crop = picture(battle, sheets, image, cache)
        if crop is not None:
            pictures[sprite] = crop
    out = assets/'thumbs'
    out.mkdir(exist_ok=True)
    for old in out.glob('atlas-*.png'):
        old.unlink()
    index = {'limit': LIMIT, 'files': [], 'sprites': {}}
    for number, (atlas, places) in enumerate(pack(pictures)):
        bottom = max(y+h for x, y, w, h in places.values())
        name = f'atlas-{number}.png'
        atlas.crop((0, 0, ATLAS, bottom)).save(out/name, optimize=True)
        index['files'].append(name)
        for sprite, (x, y, w, h) in places.items():
            index['sprites'][sprite] = [number, x, y, w, h]
    (out/'index.json').write_text(json.dumps(index, separators=(',', ':'))+'\n')
    return index


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', default='client/assets/legacy')
    args = parser.parse_args()
    result = build(Path(args.assets))
    size = sum((Path(args.assets)/'thumbs'/name).stat().st_size for name in result['files'])
    print(f"{len(result['sprites'])} thumbnails in {len(result['files'])} atlases, {size/1e6:.1f} MB")
