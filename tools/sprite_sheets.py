"""Sprite sheets for imported frame art (docs/technical/sprite-sheets.md).

The original client keeps every animation frame as its own bitmap. Importers
pack the frames of one animated thing (a rider and mount composite, a battle
sprite, a walking character) into one sheet with pack_sheets, save it with
save_sheet (a lossless 256-colour PNG when possible), and record each frame's
place in a manifest `sheets` entry: {files, frames: bitmap -> [sheet, x, y, w, h]}.
"""
from PIL import Image

SHEET_LIMIT = 4096
PADDING = 1


def pack_sheets(frames, limit=SHEET_LIMIT, padding=PADDING):
    """Shelf-packs frame images into as few sheets as fit within limit x limit.

    frames maps a bitmap id to its image. Returns (sheets, placements): the
    sheet images and, per id, [sheet, x, y, w, h]. Frames are padded with
    transparent pixels so neighbours never bleed into a scaled frame.
    """
    order = sorted(frames, key=lambda i: (-frames[i].height, -frames[i].width, i))
    area = sum((frames[i].width + padding) * (frames[i].height + padding) for i in order)
    widest = max((frames[i].width + padding for i in order), default=1)
    width = min(limit, max(widest, 1 << max(0, int((area ** 0.5) * 1.1) - 1).bit_length()))
    layouts, placements = [[]], {}
    x = y = shelf = 0
    for ident in order:
        w, h = frames[ident].size
        if w + padding > limit or h + padding > limit:
            raise ValueError(f'Frame {ident} ({w}x{h}) is larger than a {limit}px sheet')
        if x + w + padding > width:
            x, y, shelf = 0, y + shelf, 0
        if y + h + padding > limit:
            layouts.append([])
            x = y = shelf = 0
        layouts[-1].append((ident, x, y))
        placements[ident] = [len(layouts) - 1, x, y, w, h]
        x += w + padding
        shelf = max(shelf, h + padding)
    sheets = []
    for layout in layouts:
        right = max(x + frames[i].width for i, x, _ in layout)
        bottom = max(y + frames[i].height for i, _, y in layout)
        sheet = Image.new('RGBA', (right, bottom), (0, 0, 0, 0))
        for ident, x, y in layout:
            sheet.paste(frames[ident].convert('RGBA'), (x, y))
        sheets.append(sheet)
    return sheets, placements


def to_palette(sheet):
    """The sheet as an 8-bit palette image when that is lossless.

    The original art is 256-colour with on/off transparency, so a sheet
    almost always fits: index 0 is transparent and the rest are its colours.
    Anything else (partial alpha, too many colours) stays RGBA.
    """
    colors = sheet.getcolors(257)
    if colors is None or any(c[3] not in (0, 255) for _, c in colors):
        return sheet
    opaque = sorted({c[:3] for _, c in colors if c[3] == 255})
    if not opaque or len(opaque) > 255:
        return sheet
    key = next(c for c in [(255, 0, 255), (0, 255, 255), (1, 2, 3)] + [(i, 7, 11) for i in range(256)] if c not in opaque)
    entries = [key] + opaque
    entries += [opaque[0]] * (256 - len(entries))
    # Pillow quantize(palette=...) uses an approximate colour lookup, even
    # without dithering: nearby original colours can collapse to one index.
    # These pixels already belong to this exact palette; map them directly.
    lookup = {color: i + 1 for i, color in enumerate(opaque)}
    indices = bytes(lookup[pixel[:3]] if pixel[3] else 0 for pixel in sheet.getdata())
    result = Image.frombytes('P', sheet.size, indices)
    result.putpalette([v for color in entries for v in color])
    result.info['transparency'] = 0
    return result


def save_sheets(frames, folder, stem):
    """Packs frames into folder/<stem>.png (or <stem>-<n>.png when it needs
    several sheets). Returns the manifest entry, file names relative to folder."""
    sheets, placements = pack_sheets(frames)
    files = []
    for index, sheet in enumerate(sheets):
        name = f'{stem}.png' if len(sheets) == 1 else f'{stem}-{index}.png'
        sheet = to_palette(sheet)
        sheet.save(folder / name, optimize=True, **({'transparency': 0} if sheet.mode == 'P' else {}))
        files.append(name)
    return dict(files=files, frames={str(i): p for i, p in placements.items()})
