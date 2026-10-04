"""Draft same-pose masks from independently annotated dragon regions.

No colour vote: only dragon-labelled reference pixels contribute. Conflicting
source or target colours are rejected, not counted. Coincident rider colours
are STILL possible, so every new bitmap remains unreviewed and unshippable.
"""
import argparse
import copy
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from audit_red_dragon_recolor import align, digest, indices
from import_legacy import Archive
from recolor_red_dragon_samples import BODY, VENTRAL, masks, recolor, validate_source


def row_runs(mask):
    runs=[]
    for y,row in enumerate(mask):
        transitions=np.diff(np.r_[False,row,False].astype(np.int8))
        starts=np.flatnonzero(transitions==1);ends=np.flatnonzero(transitions==-1)-1
        runs.extend([[y,int(a),int(b)] for a,b in zip(starts,ends)])
    return runs


def enclosed(mask):
    """Fill only enclosed holes; this is a draft guard, never a rider label."""
    h,w=mask.shape;outside=np.zeros_like(mask);stack=[]
    for x in range(w):
        if not mask[0,x]:outside[0,x]=True;stack.append((0,x))
        if not mask[h-1,x]:outside[h-1,x]=True;stack.append((h-1,x))
    for y in range(1,h-1):
        if not mask[y,0]:outside[y,0]=True;stack.append((y,0))
        if not mask[y,w-1]:outside[y,w-1]=True;stack.append((y,w-1))
    while stack:
        y,x=stack.pop()
        for yy,xx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
            if 0<=yy<h and 0<=xx<w and not outside[yy,xx] and not mask[yy,xx]:
                outside[yy,xx]=True;stack.append((yy,xx))
    return ~outside


def merge_references(references):
    original=np.zeros((384,384),np.uint8);red=original.copy()
    known=np.zeros_like(original,dtype=bool);conflict=known.copy()
    for pixels,changed,label in references:
        disagreement=known & label & ((original!=pixels)|(red!=changed))
        conflict |= disagreement
        fresh=label & ~known
        original[fresh]=pixels[fresh];red[fresh]=changed[fresh];known |= label
    known &= ~conflict
    return original,red,known,conflict


def draft_guard(pixels,original,known,fill_enclosed=True):
    visible=(pixels!=0)&(pixels!=168)
    unexplained=visible & (~known | (pixels!=original))
    # Small closure joins gaps in texture. A pet region enclosed by arms can
    # also be filled: that is conservative unresolved colour, NOT proof that
    # the filled region is rider. Such holes need the same visual review.
    expanded=Image.fromarray(unexplained.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3))
    closed=np.array(expanded.filter(ImageFilter.MinFilter(3)))!=0
    filled=enclosed(closed) if fill_enclosed else unexplained
    guard=np.array(Image.fromarray(filled.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3)))!=0
    return guard,unexplained,filled & ~unexplained


def respect_target_protection(candidate, rider, unknown):
    """Existing independent protection wins even when reference colours match."""
    collisions=candidate & (rider | unknown)
    return candidate & ~collisions, collisions


def run(source,ledger_path,rule_paths,pages,output,fill_enclosed=True):
    archive=Archive(source);ledger=json.loads(ledger_path.read_text());annotated={};padding={}
    for path in rule_paths:
        book=json.loads(path.read_text())
        if book['source_palette_sha256']!=ledger['source_palette_sha256']:
            raise ValueError('Reference palette mismatch')
        for key,rule in book['records'].items():
            annotated[key]=rule;padding[key]=book['rider_boundary_dilation']
    result=dict(format=1,status='UNREVIEWED_REFERENCE_REGION_DRAFTS',
                source_palette_sha256=ledger['source_palette_sha256'],rider_boundary_dilation=0,records={})
    summaries=[]
    for page_no in pages:
        page=ledger['pages'][page_no];reference_ids=[b for b in page['bitmaps'] if str(b) in annotated]
        if not reference_ids:raise ValueError(f'No independently prepared reference for page {page_no}')
        refs={}
        for bitmap in reference_ids:
            rule=annotated[str(bitmap)]
            if rule.get('review_status','').startswith(('DRAFT: translated','NEEDS_NEW_ANNOTATION')):
                raise ValueError(f'Automatic draft cannot serve as independent reference: {bitmap}')
            p=validate_source(archive,bitmap,rule);changed,labels=recolor(p,rule,padding[str(bitmap)])
            frame=next(s for s in rule['slots'] if s['clip']==page['slots'][0]['clip'] and s['frame']==page['slots'][0]['frame'])['sprite_frame']
            original,_=align(archive,bitmap,p,frame);red,_=align(archive,bitmap,changed,frame)
            label,_=align(archive,bitmap,labels[2].astype(np.uint8),frame)
            refs[bitmap]=(original,red,label!=0)
        for bitmap in page['bitmaps']:
            # Leave the target's own annotation out; avoid tautological reuse
            # when comparing drafts to an independently reviewed source mask.
            used=[b for b in reference_ids if b!=bitmap]
            if not used:continue
            original,red,known,conflict=merge_references([refs[b] for b in used])
            record=ledger['records'][str(bitmap)];p,sha=indices(archive,bitmap)
            if sha!=record['source_rd_sha256'] or digest(p.tobytes())!=record['source_indices_sha256']:
                raise ValueError(f'Source hash mismatch: {bitmap}')
            slot=next(s for s in record['slots'] if s['clip']==page['slots'][0]['clip'] and s['frame']==page['slots'][0]['frame'])
            target,(x,y)=align(archive,bitmap,p,slot['sprite_frame']);h,w=p.shape
            guard,unexplained,holes=draft_guard(target,original,known,fill_enclosed)
            dragon=known & (target==original) & ~guard & (target!=0) & (target!=168)
            protected=np.zeros_like(dragon);collisions=np.zeros_like(dragon)
            if str(bitmap) in annotated:
                target_rule=annotated[str(bitmap)]
                validate_source(archive,bitmap,target_rule)
                rider,unknown,*_=masks(target_rule,padding[str(bitmap)])
                protected[y:y+h,x:x+w]=rider | unknown
                dragon,collisions=respect_target_protection(dragon,protected,np.zeros_like(protected))
            ventral=np.zeros_like(dragon);underwing=np.zeros_like(dragon)
            for old,new in VENTRAL.items():ventral |= dragon & (original==old) & (red==new) & (original!=red)
            for old in BODY:underwing |= dragon & (original==old) & (red==old)
            cut=lambda a:a[y:y+h,x:x+w]
            rule={k:copy.deepcopy(record[k]) for k in ('source_rd_sha256','source_indices_sha256','geometry','slots')}
            rule.update(rider_envelopes=[],uncertain_polygons=[],dragon_envelopes=[],ventral_polygons=[],
                        rider_runs=[],uncertain_runs=row_runs(cut(~dragon)),dragon_runs=row_runs(cut(dragon)),
                        ventral_runs=row_runs(cut(ventral)),underwing_preserve_runs=row_runs(cut(underwing)),
                        review_status='DRAFT: independent reference regions; target rider/occlusion not yet reviewed',
                        review='No colour majority. Conflicts rejected. Unknown includes rider and unresolved dragon, not a rider label.',
                        reference_regions={'pose_page':page_no,'bitmaps':used,'fill_enclosed_guard':fill_enclosed,
                          'source_rule_hashes':{str(b):digest(json.dumps(annotated[str(b)],sort_keys=True).encode()) for b in used},
                          'known_pixels':int(known.sum()),'conflict_pixels':int(conflict.sum()),
                          'nonmatching_visible_pixels':int(cut(unexplained).sum()),'closure_pixels':int(cut(holes).sum()),
                          'existing_target_protection_applied':str(bitmap) in annotated,
                          'candidate_collisions_with_existing_protection':int(collisions.sum()),
                          'new_semantic_approval':False})
            result['records'][str(bitmap)]=rule
        summaries.append({'page':page_no,'references':reference_ids})
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'records':len(result['records']),'pages':summaries,'new_semantic_approvals':0,
                      'sha256':digest(output.read_bytes())}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','ledger','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--rules',type=Path,nargs='+',required=True)
    parser.add_argument('--pages',type=int,nargs='+',required=True)
    parser.add_argument('--local-guard',action='store_true',help='Draft only: do not fill regions enclosed by rider arms; requires renewed target inspection')
    args=parser.parse_args();run(args.source,args.ledger,args.rules,args.pages,args.output,not args.local_guard)
