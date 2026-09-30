"""Compact map files (`world/<id>.map`) and the conversion from map JSON.

Map JSON parsed in Godot costs 10 to 20 times its size: every ground cell is
its own Array of Variants (docs/technical/memory-baseline.md). A `.map` file
keeps the small fields as JSON and the grids as raw little-endian arrays that
the game reads straight into packed arrays (client/scripts/map_file.gd):

    b'SAMAP\\0' + uint16 version (1)
    uint32 n, n bytes of UTF-8 JSON: every field except the three grids
    uint32 w*h, int32[w*h] ground: the tile image id per cell (y*w+x), 0 = none
    uint32 w*h, uint8[w*h] blocked: nonzero = not walkable
    uint32 n, int32[3n] objects: x, y, image id per object, in file order

`load_map` returns the JSON shape the importers write (ground as [x, y, id]
triples in row order), so tools read either format.

Convert the imported world maps in place (the importers write `.map` already):

    python3 tools/map_file.py [--root client/assets/legacy]
"""
import argparse
from array import array
import json
from pathlib import Path
import struct
import sys

MAGIC = b'SAMAP\0'
VERSION = 1
GRIDS = ('ground', 'blocked', 'objects')


def _int32(values):
    data = array('i', values)
    if sys.byteorder != 'little':
        data.byteswap()
    return data.tobytes()


def _read_int32(raw, offset, count):
    data = array('i')
    data.frombytes(raw[offset:offset+count*4])
    if sys.byteorder != 'little':
        data.byteswap()
    return data


def encode(data):
    """The `.map` bytes of a map in the importers' JSON shape."""
    width, height = int(data['width']), int(data['height'])
    cells = width*height
    ground = [0]*cells
    for x, y, ident in data['ground']:
        if not (0 <= x < width and 0 <= y < height):
            raise ValueError(f'ground cell outside the map: {x},{y}')
        if int(ident) <= 0:
            raise ValueError(f'ground image id must be positive: {ident}')
        ground[y*width+x] = int(ident)
    blocked = [int(v) for v in data['blocked']]
    if len(blocked) != cells or any(v < 0 or v > 255 for v in blocked):
        raise ValueError('blocked must hold one byte per cell')
    objects = [int(v) for entry in data['objects'] for v in entry]
    if any(len(entry) != 3 for entry in data['objects']):
        raise ValueError('objects must be [x, y, id] triples')
    header = json.dumps({k: v for k, v in data.items() if k not in GRIDS}, ensure_ascii=False, separators=(',', ':')).encode()
    return b''.join([MAGIC, struct.pack('<H', VERSION),
                     struct.pack('<I', len(header)), header,
                     struct.pack('<I', cells), _int32(ground),
                     struct.pack('<I', cells), bytes(blocked),
                     struct.pack('<I', len(objects)//3), _int32(objects)])


def save_map(path, data):
    Path(path).write_bytes(encode(data))


def decode(raw, header_only=False):
    if raw[:6] != MAGIC:
        raise ValueError('not a .map file')
    version, = struct.unpack_from('<H', raw, 6)
    if version != VERSION:
        raise ValueError(f'unsupported .map version {version}')
    size, = struct.unpack_from('<I', raw, 8)
    offset = 12+size
    data = json.loads(raw[12:offset].decode())
    if header_only:
        return data
    width = int(data['width'])
    cells, = struct.unpack_from('<I', raw, offset)
    if cells != width*int(data['height']):
        raise ValueError('ground size does not match the map')
    ground = _read_int32(raw, offset+4, cells)
    offset += 4+cells*4
    cells, = struct.unpack_from('<I', raw, offset)
    blocked = list(raw[offset+4:offset+4+cells])
    offset += 4+cells
    count, = struct.unpack_from('<I', raw, offset)
    flat = _read_int32(raw, offset+4, count*3)
    if offset+4+count*12 != len(raw):
        raise ValueError('.map file has trailing or missing bytes')
    data['ground'] = [[i % width, i//width, ident] for i, ident in enumerate(ground) if ident]
    data['blocked'] = blocked
    data['objects'] = [list(flat[i:i+3]) for i in range(0, len(flat), 3)]
    return data


def load_map(path, header_only=False):
    """A map in the JSON shape, from a `.map` or a map JSON file."""
    path = Path(path)
    if path.suffix == '.map':
        return decode(path.read_bytes(), header_only)
    return json.loads(path.read_text())


def same_map(a, b):
    """True when two maps in the JSON shape draw and walk the same."""
    def cells(data):
        width = int(data['width'])
        return {y*width+x: int(i) for x, y, i in data['ground']}
    rest = lambda d: {k: v for k, v in d.items() if k not in GRIDS}
    return (rest(a) == rest(b) and cells(a) == cells(b) and len(cells(a)) == len(a['ground'])
            and [int(v) for v in a['blocked']] == [int(v) for v in b['blocked']]
            and [list(map(int, o)) for o in a['objects']] == [list(map(int, o)) for o in b['objects']])


def convert_world(root):
    """Writes world/<id>.map for each world/<id>.json, checks it reads back the
    same, removes the JSON and points world/manifest.json at the new files."""
    world = Path(root)/'world'
    converted = 0
    for path in sorted(world.glob('*.json')):
        if not path.stem.isdigit():
            continue
        data = json.loads(path.read_text())
        target = path.with_suffix('.map')
        save_map(target, data)
        if not same_map(data, load_map(target)):
            target.unlink()
            raise ValueError(f'{target} does not read back as {path}')
        path.unlink()
        converted += 1
    manifest_path = world/'manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        changed = False
        for info in manifest.get('maps', {}).values():
            if str(info.get('path', '')).endswith('.json'):
                info['path'] = info['path'][:-5]+'.map'
                changed = True
            if not (Path(root)/info['path']).exists():
                raise ValueError(f'missing map file {info["path"]}')
        if changed:
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    return converted


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', default='client/assets/legacy')
    args = parser.parse_args()
    print(f'converted {convert_world(args.root)} maps to .map')
