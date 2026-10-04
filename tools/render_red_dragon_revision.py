"""Inspect actual pixel revisions without treating unchanged output as new review.

Source/previous/current/delta crops include every changed pixel. Output and source
hashes are recorded; this generates evidence, never a semantic approval receipt.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(previous, current, output, bitmaps):
    output.mkdir(parents=True, exist_ok=True)
    records=[];tiles=[]
    for bitmap in bitmaps:
        paths=[current/f'{bitmap}-original.png', previous/f'{bitmap}-red.png', current/f'{bitmap}-red.png']
        source_old=previous/f'{bitmap}-original.png'
        if digest(paths[0]) != digest(source_old):
            raise ValueError(f'{bitmap}: source changed between revisions')
        pictures=[Image.open(p).convert('RGBA') for p in paths]
        if len({p.size for p in pictures}) != 1:
            raise ValueError(f'{bitmap}: geometry changed')
        before,after=map(np.asarray,pictures[1:])
        delta=np.any(before!=after,axis=2)
        y,x=np.where(delta)
        record={'bitmap':bitmap,'source_sha256':digest(paths[0]),'previous_sha256':digest(paths[1]),
                'current_sha256':digest(paths[2]),'changed_pixels':int(delta.sum())}
        if len(x):
            w,h=pictures[0].size
            box=(max(0,int(x.min())-3),max(0,int(y.min())-3),min(w,int(x.max())+4),min(h,int(y.max())+4))
            # The crop must contain every revision pixel, not a chosen favourable region.
            assert int(delta[box[1]:box[3],box[0]:box[2]].sum()) == int(delta.sum())
            marks=np.asarray(pictures[0]).copy();marks[delta]=[255,0,255,255]
            pictures.append(Image.fromarray(marks))
            iw,ch=(box[2]-box[0])*5,(box[3]-box[1])*5
            cw=max(100,iw)
            tile=Image.new('RGB',((cw+12)*4,max(ch+45,65)),'#555555');draw=ImageDraw.Draw(tile)
            for i,pic in enumerate(pictures):
                crop=pic.crop(box).resize((iw,ch),Image.Resampling.NEAREST)
                tile.paste(crop,(i*(cw+12),40),crop)
                draw.text((i*(cw+12)+2,20),['SOURCE','PREVIOUS','CURRENT','REVISION'][i],fill='white')
            draw.text((2,3),f'{bitmap} box={box} revision={len(x)} pixels',fill='white')
            record['crop_box']=list(box);tiles.append(tile)
        records.append(record)
    sheets=[]
    for n in range(0,len(tiles),3):
        group=tiles[n:n+3];sheet=Image.new('RGB',(max(t.width for t in group),sum(t.height+10 for t in group)),'#555555');y=0
        for tile in group:sheet.paste(tile,(0,y));y+=tile.height+10
        path=output/f'revision-{n//3}.png';sheet.save(path);sheets.append({'file':path.name,'sha256':digest(path)})
    result={'status':'REVISION_EVIDENCE_NOT_APPROVAL','previous':str(previous),'current':str(current),'records':records,'sheets':sheets}
    (output/'revision-hashes.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'bitmaps':len(records),'changed_bitmaps':len(tiles),'sheets':len(sheets)}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('previous','current','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--bitmaps',type=int,nargs='+',required=True)
    args=parser.parse_args();run(args.previous,args.current,args.output,args.bitmaps)
