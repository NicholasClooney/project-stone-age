"""Reproducible, non-shipping red mount segmentation experiment.

Only writes diagnostics to --output. A cross-body colour consensus is NOT an
independent rider mask, so this tool deliberately cannot create game manifests.
Original RD bytes and geometry are immutable. No AI or hand-painted pixels.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from import_legacy import Archive, decode_rle, sprite_animations

# Both ramps occur in the original naked red 100360. This is an experimental
# rank mapping, not an original palette swap (the species have different art).
COLOURS = {**dict(zip(range(212, 219), range(224, 231))),
           **dict(zip(range(73, 86), [224, 224, 225, 225, 226, 226, 227,
                                     228, 229, 230, 231, 232, 233]))}
BODIES = tuple(101307 + 8 * body for body in range(12))
KNOWN_RIDER_RECTS = {251083: (45, 23, 56, 35),
                     250967: (39, 25, 47, 35),
                     272413: (39, 12, 46, 20)}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def indices(archive, ident):
    e = archive.entries[ident]
    archive.real.seek(e['offset'])
    raw = archive.real.read(e['length'])
    if raw[:2] != b'RD':
        raise ValueError(f'Bad RD {ident}')
    count = e['w'] * e['h']
    data = decode_rle(raw[16:], count) if raw[2] & 1 else raw[16:16+count]
    return np.frombuffer(bytes(data), np.uint8).reshape(e['h'], e['w'])[::-1].copy(), digest(raw)


def align(archive, ident, pixels, frame):
    # Match engine offsets, including per-frame SPR offsets. No scaling.
    e = archive.entries[ident]
    x, y = e['x'] + frame['x'] + 192, e['y'] + frame['y'] + 230
    canvas = np.zeros((384, 384), np.uint8)
    h, w = pixels.shape
    if min(x, y) < 0 or x+w > 384 or y+h > 384:
        raise ValueError(f'Canvas bounds {ident}')
    canvas[y:y+h, x:x+w] = pixels
    return canvas, (x, y)


def candidate(pixels, support, threshold):
    mask = np.isin(pixels, list(COLOURS)) & (support >= threshold)
    output = pixels.copy()
    for old, new in COLOURS.items():
        output[mask & (pixels == old)] = new
    return output, mask


def rgba(pixels, palette):
    return Image.fromarray(np.dstack((np.array(palette, np.uint8)[pixels],
                                     (pixels != 0).astype(np.uint8)*255)))


def run(source, output):
    output.mkdir(parents=True, exist_ok=True)
    archive = Archive(source)
    clips = [sprite_animations(archive, b, range(13)) for b in BODIES]
    coverage = {str(b): {'clips': len(c), 'slots': sum(len(a['frames']) for a in c.values()),
                         'unique_bitmaps': len({f['image'] for a in c.values() for f in a['frames']}),
                         'animations_sha256': digest(json.dumps(c, sort_keys=True).encode())}
                for b, c in zip(BODIES, clips)}
    records, decoded = [], {}
    # Two bodies, three directions, three actions. First and middle frames.
    # Detailed evidence includes all 12 source bodies used by the consensus.
    for action in (3, 4, 0):
        for slot_kind in ('first', 'middle'):
            sheet = Image.new('RGB', (1440, 980), '#555555')
            draw = ImageDraw.Draw(sheet)
            draw.text((12, 5), f'EXPERIMENT ONLY action={action} frame={slot_kind}; original | candidate | changed=magenta, unresolved=cyan', fill='white')
            for row, (body, direction) in enumerate((b, d) for b in (1, 8) for d in (2, 4, 6)):
                key = f'{action}_{direction}'
                frame_i = 0 if slot_kind == 'first' else len(clips[body][key]['frames']) // 2
                aligned, origins, ids = [], [], []
                for c in clips:
                    f = c[key]['frames'][frame_i]; ident = f['image']; ids.append(ident)
                    if ident not in decoded: decoded[ident] = indices(archive, ident)
                    p, origin = align(archive, ident, decoded[ident][0], f)
                    aligned.append(p); origins.append(origin)
                stack = np.stack(aligned)
                original = stack[body]
                support = np.sum(stack == original, axis=0)
                changed, mask = candidate(original, support, 6)
                repeat, _ = candidate(original, support, 6)
                _, strict_mask = candidate(original, support, 12)
                unresolved = np.isin(original, list(COLOURS)) & ~mask
                assert np.array_equal(changed, repeat)
                assert np.array_equal(changed == 0, original == 0)
                assert np.array_equal(changed[~mask], original[~mask])
                ident = ids[body]; p = decoded[ident][0]; x, y = origins[body]
                h, w = p.shape
                before = rgba(p, archive.palette)
                after = rgba(changed[y:y+h, x:x+w], archive.palette)
                overlay = rgba(p, archive.palette)
                overlay_data = np.array(overlay)
                overlay_data[mask[y:y+h, x:x+w]] = (255, 0, 255, 255)
                overlay_data[unresolved[y:y+h, x:x+w]] = (0, 255, 255, 255)
                overlay = Image.fromarray(overlay_data)
                item = dict(body=BODIES[body], clip=key, frame=frame_i, bitmap=ident,
                            geometry={k: archive.entries[ident][k] for k in ('x','y','w','h')},
                            sprite_frame=clips[body][key]['frames'][frame_i],
                            duration_ms=clips[body][key]['duration_ms'],
                            original_rd_sha256=decoded[ident][1], original_indices_sha256=digest(p.tobytes()),
                            candidate_indices_sha256=digest(changed[y:y+h,x:x+w].tobytes()),
                            changed_pixels=int(mask.sum()), unanimous_changed_pixels=int(strict_mask.sum()),
                            unresolved_colour_pixels=int(unresolved.sum()),
                            rider_bit_exact_proven=False,
                            mechanical_checks=dict(repeat_hash=True, alpha_equal=True, outside_candidate_mask_equal=True))
                if ident in KNOWN_RIDER_RECTS:
                    l,t,r,b = KNOWN_RIDER_RECTS[ident]
                    item['known_rider_rect'] = [l,t,r,b]
                    item['known_rider_rect_changed'] = int(mask[y+t:y+b,x+l:x+r].sum())
                records.append(item)
                for col, im in enumerate((before, after, overlay)):
                    im = im.resize((w*2,h*2), Image.Resampling.NEAREST)
                    # Source crops are preserved separately; overview uses 1x if > row.
                    if im.height > 145:
                        im = im.resize((w,h), Image.Resampling.NEAREST)
                    left, top = col*480+180, row*158+32
                    sheet.paste(im,(left,top),im)
                    draw.text((col*480+8,top),f'{ident} {key} #{frame_i}\nbody {body}',fill='white')
                before.save(output/f'{ident}-original.png')
                after.save(output/f'{ident}-candidate.png')
                overlay.save(output/f'{ident}-mask.png')
            sheet.save(output/f'comparison-action-{action}-{slot_kind}.png')
    # Re-read every sampled source record to detect accidental source mutation.
    assert all(indices(archive, ident)[1] == sha for ident, (_, sha) in decoded.items())
    report = dict(status='UNPROVEN_NOT_FOR_IMPORT', main_base='930a9249',
                  method='same aligned palette index in >=6 of 12 bodies; NOT semantic ground truth',
                  palette_mapping=COLOURS, source_coverage=coverage, samples=records,
                  source_bitmaps_read=len(decoded), original_rd_records_unchanged=True,
                  source_files={str(p.relative_to(archive.source)):digest(p.read_bytes())
                                for p in (archive.adrn_path,archive.spradrn_path,archive.spr_path,archive.palette_path)},
                  limitation='Consensus can preserve coincident rider colours and miss partially occluded dragon. White belly/teeth and shadows are unchanged. No production manifests emitted.')
    (output/'experiment.json').write_text(json.dumps(report, indent=2)+'\n')
    hashes = {p.name:digest(p.read_bytes()) for p in sorted(output.glob('*.png'))}
    (output/'image-hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print(json.dumps({'samples':len(records),'decoded':len(decoded),'status':report['status']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    run(args.source, args.output)
