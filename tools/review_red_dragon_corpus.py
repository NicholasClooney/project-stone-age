"""Build the complete immutable-source review ledger, never a game manifest.

Pages group equal animation slots across all twelve bodies. A page is only an
aid to inspection: neither reading a page nor sharing a pose approves a mask.
Every bitmap needs its own source/rule-bound semantic receipt before shipping.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw
from audit_red_dragon_recolor import BODIES, digest, indices, rgba
from import_legacy import Archive, sprite_animations


def stable_hash(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def inventory(archive):
    clips = {body: sprite_animations(archive, body, range(13)) for body in BODIES}
    records, groups = {}, {}
    for key in sorted(clips[BODIES[0]], key=lambda k: tuple(map(int, k.split('_')))):
        lengths = {len(clips[body][key]['frames']) for body in BODIES}
        if len(lengths) != 1:
            raise ValueError(f'Body frame counts differ: {key}')
        for frame in range(lengths.pop()):
            group = tuple(clips[body][key]['frames'][frame]['image'] for body in BODIES)
            groups.setdefault(group, []).append({'clip': key, 'frame': frame})
            for body, bitmap in zip(BODIES, group):
                if bitmap not in records:
                    pixels, raw_hash = indices(archive, bitmap)
                    records[bitmap] = dict(
                        bitmap=bitmap, source_rd_sha256=raw_hash,
                        source_indices_sha256=digest(pixels.tobytes()),
                        geometry={k: archive.entries[bitmap][k] for k in ('x','y','w','h')},
                        slots=[], review_status='UNREVIEWED')
                records[bitmap]['slots'].append(dict(
                    body=body, clip=key, frame=frame,
                    sprite_frame=clips[body][key]['frames'][frame],
                    duration_ms=clips[body][key]['duration_ms']))
    coverage = {str(body): dict(clips=len(cs), positions=sum(len(c['frames']) for c in cs.values()),
                               bitmaps=len({f['image'] for c in cs.values() for f in c['frames']}),
                               animation_sha256=stable_hash(cs)) for body,cs in clips.items()}
    if any((c['clips'], c['positions'], c['bitmaps']) != (104,440,368) for c in coverage.values()):
        raise ValueError(f'Unexpected source coverage: {coverage}')
    if len(records) != 4416 or len(groups) != 368:
        raise ValueError('Unexpected unique bitmap / pose group count')
    pages = [dict(page=n, file=f'pose-{n:03d}.png', bitmaps=list(ids), slots=slots)
             for n,(ids,slots) in enumerate(groups.items())]
    return dict(format=1, status='SOURCE_REVIEW_LEDGER_NOT_APPROVAL',
                source_palette_sha256=digest(archive.palette_path.read_bytes()),
                coverage=coverage, records={str(k):v for k,v in records.items()}, pages=pages)


def approved_rule(record, rule, receipt):
    """Fail closed after any source/geometry/slot/mask change or missing review.

    A receipt records actual independent inspection; this tool does not create
    receipts from templates, majority votes, or a successful mechanical check.
    """
    if receipt.get('status') != 'independently-reviewed':
        return False
    source = {k:record[k] for k in ('source_rd_sha256','source_indices_sha256','geometry','slots')}
    return (all(rule.get(k) == v for k,v in source.items())
            and receipt.get('source_sha256') == stable_hash(source)
            and receipt.get('rule_sha256') == stable_hash(rule)
            and all(receipt.get(k) is True for k in
                    ('rider_complete','dragon_materials_complete','occlusion_reviewed')))


def require_complete_review(ledger, rules, receipts):
    expected=set(ledger['records'])
    supplied=set(rules['records'])
    if expected != supplied:
        raise ValueError(f'Rule coverage mismatch: missing {len(expected-supplied)}, extra {len(supplied-expected)}')
    if rules.get('source_palette_sha256') != ledger['source_palette_sha256']:
        raise ValueError('Rule palette mismatch')
    failed=[bitmap for bitmap in sorted(expected) if not approved_rule(
        ledger['records'][bitmap],rules['records'][bitmap],receipts.get(bitmap,{}))]
    if failed:
        raise ValueError(f'Independent semantic review missing or stale: {len(failed)} bitmaps; first {failed[:8]}')
    return len(expected)


def run(source, output):
    archive = Archive(source)
    ledger = inventory(archive)
    output.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for page in ledger['pages']:
        canvas=Image.new('RGB',(1440,1260),'#555555'); draw=ImageDraw.Draw(canvas)
        draw.text((12,8),f"SOURCE ONLY / NOT REVIEW APPROVAL - {page['slots']}",fill='white')
        for n,bitmap in enumerate(page['bitmaps']):
            record=ledger['records'][str(bitmap)]
            pixels,rd_hash=indices(archive,bitmap)
            if rd_hash != record['source_rd_sha256']:
                raise ValueError(f'Source changed during decode: {bitmap}')
            im=rgba(pixels,archive.palette); scale=3
            if im.width*scale>342 or im.height*scale>375: scale=2
            x=n%4*360+18;y=n//4*408+48
            draw.text((x,y-25),f"body {n} / {BODIES[n]} / bitmap {bitmap} / {scale}x",fill='white')
            im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
            canvas.paste(im,(x,y),im)
        target=output/page['file'];canvas.save(target)
        hashes[page['file']]=digest(target.read_bytes())
    ledger['page_hashes']=hashes
    target=output/'ledger.json';target.write_text(json.dumps(ledger,indent=2)+'\n')
    print(json.dumps(dict(bitmaps=len(ledger['records']),positions=sum(c['positions'] for c in ledger['coverage'].values()),
                          pages=len(ledger['pages']),ledger_sha256=digest(target.read_bytes()))))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();run(args.source,args.output)
