"""Decode the active Windows SA_MOUSE1 cursor, including its AND transparency mask."""
import argparse
import hashlib
import json
import struct
from pathlib import Path
from PIL import Image


def decode_cursor(data):
    if len(data) < 62 or struct.unpack_from('<HHH', data) != (0, 2, 1):
        raise ValueError('Expected one Windows CUR image')
    width, height, _, _, hot_x, hot_y, length, offset = struct.unpack_from('<BBBBHHII', data, 6)
    width, height = width or 256, height or 256
    if offset < 22 or offset + length > len(data) or hot_x >= width or hot_y >= height:
        raise ValueError('Invalid cursor extent or hotspot')
    header, dib_width, dib_height, planes, depth, compression = struct.unpack_from('<IiiHHI', data, offset)
    if header != 40 or dib_width != width or abs(dib_height) != height * 2 or planes != 1 or compression != 0 or depth != 24:
        raise ValueError('Expected original uncompressed 24-bit cursor with AND mask')
    rgb_stride = ((width * 3 + 3) // 4) * 4
    mask_stride = ((width + 31) // 32) * 4
    pixels = offset + header
    mask = pixels + rgb_stride * height
    if mask + mask_stride * height > offset + length:
        raise ValueError('Truncated cursor bitmap or mask')
    image = Image.new('RGBA', (width, height))
    for y in range(height):
        row = height - y - 1 if dib_height > 0 else y
        for x in range(width):
            b, g, r = data[pixels + row * rgb_stride + x * 3:pixels + row * rgb_stride + x * 3 + 3]
            transparent = data[mask + row * mask_stride + x // 8] & (0x80 >> (x % 8))
            image.putpixel((x, y), (r, g, b, 0 if transparent else 255))
    return image, [hot_x, hot_y]


def run(source, output):
    source, output = Path(source), Path(output)
    data = source.read_bytes()
    image, hotspot = decode_cursor(data)
    output.mkdir(parents=True, exist_ok=True)
    image.save(output / 'stone-fish.png')
    manifest = {'path': 'stone-fish.png', 'size': list(image.size), 'hotspot': hotspot,
                'source': 'SA_MOUSE1 / Script1.rc:37 / 123.cur',
                'source_sha256': hashlib.sha256(data).hexdigest(),
                'context': 'main.cpp:718 and talkwindow.cpp:128 load the same resource; no verified alternate states'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Imported original {image.width}x{image.height} stone-fish cursor, hotspot {hotspot}')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='Path to reference client 123.cur')
    parser.add_argument('--output', default='client/assets/legacy/cursor')
    args = parser.parse_args()
    run(args.source, args.output)
