"""Translate inspected polygon parts into same-direction review drafts.

Exact indexed-pixel agreement ranks translations, but is NOT semantic truth.
Every result remains DRAFT, including a perfect match: another frame can put a
dragon wing over the rider. No receipts or production manifests are written.
"""
import argparse
import copy
import json
from pathlib import Path

import numpy as np
from audit_red_dragon_recolor import digest, indices
from import_legacy import Archive
from recolor_red_dragon_samples import raster


def translate_part(source, target, polygon, predicted, radius=12):
    mask=raster((source.shape[1],source.shape[0]),[polygon]) & (source!=0) & (source!=168)
    yy,xx=np.where(mask); values=source[yy,xx]
    if not len(values):
        return None, {'status':'NO_VISIBLE_SOURCE_PIXELS'}
    best=None
    for dy in range(predicted[1]-radius,predicted[1]+radius+1):
        for dx in range(predicted[0]-radius,predicted[0]+radius+1):
            tx,ty=xx+dx,yy+dy
            valid=(tx>=0)&(ty>=0)&(tx<target.shape[1])&(ty<target.shape[0])
            matched=int(np.count_nonzero(target[ty[valid],tx[valid]]==values[valid]))
            rank=(matched,-abs(dx-predicted[0])-abs(dy-predicted[1]))
            if best is None or rank>best[0]:best=(rank,dx,dy)
    rank,dx,dy=best
    proposed=[[x+dx,y+dy] for x,y in polygon]
    clipped=any(x<0 or y<0 or x>=target.shape[1] or y>=target.shape[0] for x,y in proposed)
    proposed=[[max(0,min(target.shape[1]-1,x)),max(0,min(target.shape[0]-1,y))] for x,y in proposed]
    comparable=rank[0]/len(values)>=0.95 and not clipped
    return proposed,dict(status='DRAFT_REQUIRES_OCCLUSION_REVIEW' if comparable else 'TEMPLATE_NOT_COMPARABLE',translation=[dx,dy],
                         compared_pixels=len(values),matched_pixels=rank[0],clipped=clipped)


def run(source, ledger_path, seed_path, clip, output):
    archive=Archive(source);ledger=json.loads(ledger_path.read_text());seeds=json.loads(seed_path.read_text())
    if digest(archive.palette_path.read_bytes())!=ledger['source_palette_sha256']:
        raise ValueError('Palette mismatch')
    by_body={}
    for bitmap,rule in seeds['records'].items():
        for slot in rule['slots']:
            if slot['clip']==clip and slot['frame']==0:
                by_body[slot['body']]=(int(bitmap),rule)
    target_records=[r for r in ledger['records'].values() if any(s['clip']==clip for s in r['slots'])]
    missing={r['slots'][0]['body'] for r in target_records}-by_body.keys()
    if missing:raise ValueError(f'Missing independently prepared seed bodies: {sorted(missing)}')
    result={k:copy.deepcopy(v) for k,v in seeds.items() if k!='records'}
    result.update(status='UNREVIEWED_TRANSLATION_DRAFTS',records={})
    decoded={}
    def read(bitmap,rule):
        if bitmap not in decoded:decoded[bitmap]=indices(archive,bitmap)
        p,sha=decoded[bitmap]
        if sha!=rule['source_rd_sha256'] or digest(p.tobytes())!=rule['source_indices_sha256']:
            raise ValueError(f'Source mismatch: {bitmap}')
        return p
    for record in target_records:
        body=record['slots'][0]['body'];bitmap=record['bitmap'];seed_id,seed=by_body[body]
        if bitmap==seed_id:
            result['records'][str(bitmap)]=copy.deepcopy(seed);continue
        src=read(seed_id,seed);dst=read(bitmap,record)
        predicted=(seed['geometry']['x']-record['geometry']['x'],seed['geometry']['y']-record['geometry']['y'])
        rule={k:copy.deepcopy(record[k]) for k in ('source_rd_sha256','source_indices_sha256','geometry','slots')}
        rule.update(review_status='DRAFT: translated parts; no per-bitmap semantic approval',
                    review='Not independently reviewed. Pixel match scores cannot establish rider identity or occlusion.',
                    uncertain_polygons=[],part_matches={},rider_boundary_dilation=seeds['rider_boundary_dilation'])
        for field in ('rider_envelopes','ventral_polygons','underwing_preserve_polygons'):
            rule[field]=[];rule['part_matches'][field]=[]
            for poly in seed.get(field,[]):
                proposal,score=translate_part(src,dst,poly,predicted)
                if proposal is not None:rule[field].append(proposal)
                rule['part_matches'][field].append(score)
        w,h=dst.shape[1],dst.shape[0]
        rule['dragon_envelopes']=[[[0,0],[w-1,0],[w-1,h-1],[0,h-1]]]
        if any(score['status']!='DRAFT_REQUIRES_OCCLUSION_REVIEW'
               for scores in rule['part_matches'].values() for score in scores):
            # This is explicitly unknown, NOT a rider label. A weak texture
            # match must not silently turn an unrelated hat/hand into dragon.
            rule['uncertain_polygons']=copy.deepcopy(rule['dragon_envelopes'])
            rule['review_status']='NEEDS_NEW_ANNOTATION: incomparable template; entire bitmap retained as unknown'
        rule['template_provenance']={'bitmap':seed_id,'rule_sha256':digest(json.dumps(seed,sort_keys=True).encode()),
                                     'method':'part translation ranked by exact indexed pixels; NOT semantic approval'}
        result['records'][str(bitmap)]=rule
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'clip':clip,'records':len(result['records']),'source_seed_bodies':len(by_body),
                      'new_semantic_approvals':0,'sha256':digest(output.read_bytes())}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','ledger','seeds','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--clip',required=True)
    args=parser.parse_args();run(args.source,args.ledger,args.seeds,args.clip,args.output)
