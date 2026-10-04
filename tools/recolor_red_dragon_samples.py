"""Generate review-only mount samples from hash-bound spatial annotations.

No vote-derived semantic masks; no production manifest. Every input bitmap and
SPR slot must match the reviewed source. Unknown boundaries stay bit-exact.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from audit_red_dragon_recolor import digest, indices, rgba
from import_legacy import Archive, sprite_animations

BODY = {**dict(zip(range(212,223), [224,225,226,227,228,229,230,231,232,233,233])),
        **dict(zip(range(73,86), [224,224,225,225,226,226,227,228,229,230,231,232,233]))}
# Match original red throat/ventral yellow, preserving white eye/teeth/claws
# by *spatial material* polygons, not a whole-image white palette replacement.
VENTRAL = {**dict(zip(range(159,168), [212,213,214,215,216,217,218,80,81])),
           **dict(zip(range(175,192), [212,212,213,213,214,214,215,215,216,
                                      216,217,217,218,218,80,80,81]))}


def raster(size, polygons):
    image = Image.new('L', size)
    draw = ImageDraw.Draw(image)
    for poly in polygons:
        if len(poly) < 3 or any(len(p) != 2 for p in poly):
            raise ValueError('Invalid polygon')
        if any(x < 0 or y < 0 or x >= size[0] or y >= size[1] for x,y in poly):
            raise ValueError(f'Polygon outside {size}: {poly}')
        draw.polygon([tuple(p) for p in poly], fill=255)
    return np.array(image) != 0


def masks(rule, padding):
    size = rule['geometry']['w'], rule['geometry']['h']
    rider = raster(size, rule['rider_envelopes'])
    expanded = np.array(Image.fromarray(rider.astype(np.uint8)*255).filter(
        ImageFilter.MaxFilter(padding*2+1))) != 0
    unknown = raster(size, rule['uncertain_polygons']) | (expanded & ~rider)
    # Unknown has priority even if a conservative rider envelope overlaps it.
    rider &= ~unknown
    dragon = raster(size, rule['dragon_envelopes']) & ~rider & ~unknown
    ventral = raster(size, rule['ventral_polygons']) & dragon
    underwing = raster(size, rule.get("underwing_preserve_polygons", [])) & dragon
    return rider, unknown, dragon, ventral, underwing


def recolor(pixels, rule, padding):
    rider, unknown, dragon, ventral, underwing = masks(rule, padding)
    dragon &= (pixels != 0) & (pixels != 168)
    ventral &= dragon
    underwing &= dragon
    output = pixels.copy()
    for old,new in BODY.items():
        output[dragon & ~underwing & (pixels == old)] = new
    for old,new in VENTRAL.items():
        output[ventral & ~underwing & (pixels == old)] = new
    return output, (rider, unknown, dragon, ventral, underwing)


def validate_source(archive, bitmap, rule):
    p, rd_sha = indices(archive, bitmap)
    if rd_sha != rule['source_rd_sha256'] or digest(p.tobytes()) != rule['source_indices_sha256']:
        raise ValueError(f'{bitmap}: source hash mismatch')
    if {k:archive.entries[bitmap][k] for k in ('x','y','w','h')} != rule['geometry']:
        raise ValueError(f'{bitmap}: geometry mismatch')
    for slot in rule['slots']:
        clip = sprite_animations(archive, slot['body'], range(13))[slot['clip']]
        if clip['frames'][slot['frame']] != slot['sprite_frame'] or clip['duration_ms'] != slot['duration_ms']:
            raise ValueError(f'{bitmap}: SPR slot mismatch')
        if slot['sprite_frame']['image'] != bitmap:
            raise ValueError(f'{bitmap}: wrong bitmap in slot')
    return p


def run(source, rules_path, output):
    rules = json.loads(rules_path.read_text()); archive = Archive(source)
    if digest(archive.palette_path.read_bytes()) != rules['source_palette_sha256']:
        raise ValueError('Palette hash mismatch')
    output.mkdir(parents=True, exist_ok=True)
    records=[];pictures={};padding=rules['rider_boundary_dilation']
    for key,rule in rules['records'].items():
        bitmap=int(key);p=validate_source(archive,bitmap,rule)
        changed, labels = recolor(p,rule,padding)
        rider,unknown,dragon,ventral,underwing=labels;diff=changed!=p
        assert not np.any(diff & (rider | unknown | underwing | ~dragon))
        assert np.array_equal(p==0,changed==0)
        assert np.array_equal(changed[p==168],p[p==168])
        assert np.array_equal(changed, recolor(p,rule,padding)[0])
        before,after=rgba(p,archive.palette),rgba(changed,archive.palette)
        visible=p!=0;rgb=np.array(before)
        # Separate protected envelope (may contain dragon), unknown, and
        # explicit material semantics. Do not claim all unchanged pixels rider.
        for mask,colour in [(rider,(60,140,255)),(unknown,(255,160,0)),
                            (dragon,(80,220,100)),(ventral,(255,255,0)),(underwing,(220,100,220))]:
            selected=mask & visible
            rgb[selected,:3]=(rgb[selected,:3].astype(np.uint16)//2 + np.array(colour)//2).astype(np.uint8)
        overlay=Image.fromarray(rgb)
        for name,im in [('original',before),('red',after),('labels',overlay)]:
            im.save(output/f'{bitmap}-{name}.png')
        # Save exact independent binary labels for downstream review/tests.
        for name,mask in zip(('protected-envelope','unknown','dragon','ventral','underwing-preserved'),labels):
            Image.fromarray(mask.astype(np.uint8)*255).save(output/f'{bitmap}-{name}.png')
        Image.fromarray(diff.astype(np.uint8)*255).save(output/f'{bitmap}-diff.png')
        w,h=before.size
        comparison=Image.new('RGB', ((w*4+24)*4,h*4+52),'#555555')
        cd=ImageDraw.Draw(comparison)
        difference=Image.fromarray(np.dstack((np.where(diff,255,0).astype(np.uint8),np.zeros_like(p),np.where(diff,255,0).astype(np.uint8),np.full_like(p,255))))
        for col,(title,im) in enumerate(zip(('ORIGINAL','RED SPATIAL SAMPLE','BLUE protected / ORANGE unknown','MAGENTA actual differences'),(before,after,overlay,difference))):
            x=col*(w*4+24)+12
            cd.text((x,8),str(bitmap)+' '+title,fill='white')
            im=im.resize((w*4,h*4),Image.Resampling.NEAREST)
            comparison.paste(im,(x,36),im)
        comparison.save(output/f'{bitmap}-comparison.png')
        record={'bitmap':bitmap,'slots':rule['slots'],'geometry':rule['geometry'],
                'source_rd_sha256':rule['source_rd_sha256'],
                'source_indices_sha256':digest(p.tobytes()),'output_indices_sha256':digest(changed.tobytes()),
                'rule_sha256':digest(json.dumps(rule,sort_keys=True).encode()),
                'labels_sha256':{name:digest(mask.tobytes()) for name,mask in zip(('protected','unknown','dragon','ventral','underwing-preserved'),labels)},
                'changed_pixels':int(diff.sum()),'protected_envelope_changed':int((diff&rider).sum()),
                'unknown_changed':int((diff&unknown).sum()),'outside_dragon_changed':int((diff&~dragon).sum()),
                'underwing_preserved_pixels':int(underwing.sum()),'underwing_changed':int((diff&underwing).sum()),
                'ventral_white_to_yellow':int((diff&ventral&np.isin(p,list(VENTRAL))).sum()),
                'unknown_potential_body_colour':int((unknown&np.isin(p,list(BODY))).sum()),
                'protected_envelope_potential_body_colour':int((rider&np.isin(p,list(BODY))).sum()),
                'geometry_timing_verified':True,'alpha_identical':True,'shadow_identical':True,
                'annotation_status':'agent-reviewed conservative sample; user art review pending'}
        record['review_points'] = [dict(point, original_index=int(p[point['xy'][1], point['xy'][0]]), output_index=int(changed[point['xy'][1],point['xy'][0]]), changed=bool(diff[point['xy'][1],point['xy'][0]])) for point in rule.get('review_points', [])]
        assert not any(point['changed'] for point in record['review_points'])
        records.append(record);pictures[bitmap]=(before,after,overlay)
    for action in (3,4,0):
        for kind in ('first','middle'):
            rows=[r for r in records if r['slots'][0]['clip'].startswith(str(action)+'_')
                  and ((r['slots'][0]['frame']==0)==(kind=='first'))]
            rows.sort(key=lambda r:(r['slots'][0]['body'],r['slots'][0]['clip']))
            for column,name in [(1,'red'),(2,'labels')]:
                canvas=Image.new('RGB',(1320,1060),'#555555');draw=ImageDraw.Draw(canvas)
                for n,r in enumerate(rows):
                    b=r['bitmap'];im=pictures[b][column];w,h=im.size
                    im=im.resize((w*3,h*3),Image.Resampling.NEAREST)
                    x=(n%3)*440+25;y=(n//3)*530+40
                    canvas.paste(im,(x,y),im)
                    draw.text((x,y-30),f'{b} {r["slots"][0]["clip"]} frame {r["slots"][0]["frame"]} {name}',fill='white')
                    if column==2:
                        rule=rules['records'][str(b)]
                        for colour,field in [('cyan','rider_envelopes'),('orange','uncertain_polygons'),('yellow','ventral_polygons')]:
                            for poly in rule[field]:
                                pts=[(x+px*3,y+py*3) for px,py in poly];draw.line(pts+[pts[0]],fill=colour,width=1)
                        for xx in range(0,w,10):draw.text((x+xx*3,y-12),str(xx),fill='white')
                        for yy in range(0,h,10):draw.text((x-22,y+yy*3),str(yy),fill='white')
                canvas.save(output/f'{name}-{action}-{kind}.png')
    # Every sampled original record re-read after output generation.
    for key,rule in rules['records'].items():validate_source(archive,int(key),rule)
    report={'status':'REVIEWED_SPATIAL_SAMPLES_NOT_PRODUCTION','rules_sha256':digest(rules_path.read_bytes()),
            'source_palette_sha256':digest(archive.palette_path.read_bytes()),
            'material_maps':{'body':BODY,'ventral':VENTRAL},'source_records_unchanged':True,
            'semantic_limit':'Protection is conditional on reviewed polygons; no vote or blanket identity claim. Envelope includes some dragon; uncertain edges retain original colour.',
            'records':records}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    (output/'hashes.json').write_text(json.dumps({p.name:digest(p.read_bytes()) for p in sorted(output.glob('*.png'))},indent=2)+'\n')
    print(json.dumps({'samples':len(records),'changed_pixels':sum(r['changed_pixels'] for r in records),
                      'ventral_white_to_yellow':sum(r['ventral_white_to_yellow'] for r in records),
                      'unknown_body_colour_retained':sum(r['unknown_potential_body_colour'] for r in records)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--rules',type=Path,default=Path('tools/asset_rules/red_dragon_samples.json'))
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();run(args.source,args.rules,args.output)
