"""Readable original/result pages and separate actual-difference evidence."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from audit_red_dragon_recolor import digest


def run(ledger_path, render, output, pages):
    ledger=json.loads(ledger_path.read_text());report=json.loads((render/'report.json').read_text())
    records={r['bitmap']:r for r in report['records']}
    output.mkdir(parents=True,exist_ok=True)
    written={}
    for page_no in pages:
        page=ledger['pages'][page_no];ids=page['bitmaps']
        if any(b not in records for b in ids):raise ValueError(f'Missing rendered body on page {page_no}')
        ims={}
        for b in ids:
            if records[b]['source_indices_sha256']!=ledger['records'][str(b)]['source_indices_sha256']:
                raise ValueError(f'Render/source mismatch: {b}')
            before=Image.open(render/f'{b}-original.png').convert('RGBA')
            after=Image.open(render/f'{b}-red.png').convert('RGBA')
            diff=np.any(np.array(before)!=np.array(after),axis=2)
            if np.count_nonzero(diff)!=records[b]['changed_pixels']:
                raise ValueError(f'Render/difference mismatch: {b}')
            overlay=np.array(before);overlay[diff]=[255,0,255,255]
            ims[b]=(before,after,Image.fromarray(overlay))
        width=max(im[0].width for im in ims.values());height=max(im[0].height for im in ims.values())
        cw=width*4+36;ch=height*2+48
        canvas=Image.new('RGB',(cw*3,ch*4),'#555555');draw=ImageDraw.Draw(canvas)
        for n,b in enumerate(ids):
            x=n%3*cw+12;y=n//3*ch+35
            draw.text((x,y-25),f'body {n} / {b} / original | red / pose {page_no}',fill='white')
            for col,im in enumerate(ims[b][:2]):
                large=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
                canvas.paste(large,(x+col*(width*2+12),y),large)
        target=output/f'pose-{page_no:03d}-before-after.png';canvas.save(target);written[target.name]=digest(target.read_bytes())
        for group in range(4):
            cw=width*4+30;ch=height*4+40
            canvas=Image.new('RGB',(cw*3,ch*2),'#555555');draw=ImageDraw.Draw(canvas)
            for n,b in enumerate(ids[group*3:group*3+3]):
                for row,col in enumerate((0,2)):
                    x=n*cw+10;y=row*ch+30
                    draw.text((x,y-22),f'{b} body {group*3+n} '+('ORIGINAL' if row==0 else 'ACTUAL CHANGES'),fill='white')
                    im=ims[b][col];im=im.resize((im.width*4,im.height*4),Image.Resampling.NEAREST)
                    canvas.paste(im,(x,y),im)
            target=output/f'pose-{page_no:03d}-diff-{group}.png';canvas.save(target);written[target.name]=digest(target.read_bytes())
    (output/'page-hashes.json').write_text(json.dumps(written,indent=2)+'\n')
    print(json.dumps({'pages':pages,'images':len(written),'status':'INSPECTION_EVIDENCE_NOT_APPROVAL'}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('ledger','render','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--pages',type=int,nargs='+',required=True)
    args=parser.parse_args();run(args.ledger,args.render,args.output,args.pages)
