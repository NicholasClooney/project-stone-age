#!/usr/bin/env python3
"""Rewrites the map tiles and props in client/assets/legacy/images as 8-bit
PNGs that all share one palette, losslessly.

The original map art is 256-colour with on/off transparency, and every tile
and prop the importers write uses the same few hundred colours (238 with the
8.0 data). With one palette for all of them the game draws a whole map layer
through one palette material (client/scripts/palette_sheet.gd, docs/technical/
palette-textures.md): one byte a pixel on the GPU instead of four.

Index 0 is transparent (a key colour no image uses); the colours follow,
sorted. An image with partial alpha or a colour outside the palette, or all
of them when the folder has more than 255 colours, stays RGBA; the game then
draws it as before. An image already written with this palette is left
untouched, so re-runs only rewrite what changed (web packs stay cached).

Run it after the importers that write images/ (last in
scripts/setup-original-data.sh); it is safe to run again at any time.

  .tools/asset-venv/bin/python tools/palette_images.py [folder]
"""
import sys
from pathlib import Path

from PIL import Image

FOLDER = Path(__file__).resolve().parent.parent / "client/assets/legacy/images"
KEYS = [(255, 0, 255), (0, 255, 255), (1, 2, 3)] + [(i, 7, 11) for i in range(256)]


def colours(image):
    """The opaque colours of an image, or None when it has partial alpha."""
    found = image.convert("RGBA").getcolors(1 << 24)
    if any(c[3] not in (0, 255) for _, c in found):
        return None
    return {c[:3] for _, c in found if c[3] == 255}


def shared_palette(sets):
    """The palette entries (256 RGB triples) for these colour sets, or None
    when they need more than 255 colours."""
    union = set().union(*sets) if sets else set()
    if len(union) > 255:
        return None
    opaque = sorted(union) or [(0, 0, 0)]
    key = next(c for c in KEYS if c not in union)
    entries = [key] + opaque
    return entries + [opaque[0]] * (256 - len(entries))


def to_shared(image, entries):
    """The image as a 'P' image with this palette (index 0 transparent)."""
    rgba = image.convert("RGBA")
    rgb = Image.new("RGB", rgba.size, entries[0])
    rgb.paste(rgba.convert("RGB"), mask=rgba.getchannel("A"))
    palette = Image.new("P", (1, 1))
    palette.putpalette([v for c in entries for v in c])
    result = rgb.quantize(palette=palette, dither=Image.Dither.NONE)
    result.info["transparency"] = 0
    return result


def has_palette(image, entries):
    if image.mode != "P" or image.info.get("transparency") != 0:
        return False
    palette = image.getpalette()[:768]
    return palette == [v for c in entries for v in c]


def convert(folder=FOLDER):
    """Rewrites folder/*.png; returns (written, kept, rgba) counts."""
    paths = sorted(folder.glob("*.png"))
    sets = {}
    for path in paths:
        with Image.open(path) as image:
            sets[path] = colours(image)
    entries = shared_palette([s for s in sets.values() if s is not None])
    if entries is None:
        print(f"{folder}: more than 255 colours, images stay RGBA")
        return 0, 0, len(paths)
    written = kept = rgba = 0
    for path in paths:
        if sets[path] is None:
            rgba += 1
            continue
        with Image.open(path) as image:
            image.load()
        if has_palette(image, entries):
            kept += 1
            continue
        to_shared(image, entries).save(path, optimize=True, transparency=0)
        written += 1
    return written, kept, rgba


def main():
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else FOLDER
    written, kept, rgba = convert(folder)
    print(f"{folder}: {written} rewritten with the shared palette, {kept} already had it, {rgba} stay RGBA")


if __name__ == "__main__":
    main()
