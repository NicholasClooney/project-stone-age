"""Import a bounded original Sainas map area for the first encounter slice.
Keeps original logical coordinates via origin; no fabricated terrain. Inputs unchanged.
"""
from pathlib import Path
import argparse, hashlib, json, struct
from import_legacy import Archive

def run(source, server_map, output):
    output=Path(output); (output/'images').mkdir(parents=True,exist_ok=True)
    a=Archive(source); raw=Path(server_map).read_bytes()
    if len(raw)<44 or raw[:6]!=b'LS2MAP': raise ValueError('Expected LS2MAP')
    full_w,full_h=struct.unpack_from('>HH',raw,40)
    if (full_w,full_h)!=(800,800) or len(raw)!=44+full_w*full_h*4: raise ValueError('Unexpected Sainas map')
    ox,oy,w,h=592,448,96,96
    ground=[]; objects=[]; used=set(); missing=[]; blocked=[True]*(w*h)
    for y in range(h):
        for x in range(w):
            i=(y+oy)*full_w+x+ox; tile=struct.unpack_from('>H',raw,44+i*2)[0]
            prop=struct.unpack_from('>H',raw,44+full_w*full_h*2+i*2)[0]
            blocked[y*w+x]=tile in (0,1,2,5,6,9,10) or prop in (1,2,5,6,9,10)
            for value,is_prop in ((tile,False),(prop,True)):
                if value<=99: continue
                ident=a.map_ids.get(value)
                if ident is None:
                    missing.append([x+ox,y+oy,value]);blocked[y*w+x]=True;continue
                used.add(ident); e=a.entries[ident]
                (objects if is_prop else ground).append([x,y,ident])
                if not is_prop and e['hit'] in (0,2):blocked[y*w+x]=e['hit']==0
    for x,y,ident in objects:
        e=a.entries[ident]
        for dy in range(max(1,e['ey'])):
            for dx in range(max(1,e['ex'])):
                xx,yy=x+dx,y-dy
                if 0<=xx<w and 0<=yy<h and e['hit'] in (0,2):blocked[yy*w+xx]=e['hit']==0
    for x,y,_value in missing:
        blocked[(y-oy)*w+x-ox]=True
    # Bound the first slice to imported terrain; do not walk into missing content.
    for y in range(h):
        for x in range(w):
            if x<2 or y<2 or x>=w-2 or y>=h-2:blocked[y*w+x]=True
    base=json.loads((output/'samgir.json').read_text())
    images=dict(base['images'])
    colors={}
    for ident in sorted(used):
        img=a.image(ident);img.save(output/'images'/f'{ident}.png')
        e=a.entries[ident];images[str(ident)]={k:e[k] for k in ('x','y','w','h','ex','ey','hit','priority')}
        colors[str(ident)]=list(img.convert('RGB').resize((1,1)).getpixel((0,0)))
    result=dict(map_id=100,name='塞伊那斯・村外',origin=[ox,oy],width=w,height=h,ground=ground,objects=objects,blocked=[int(v) for v in blocked],images=images,characters=base['characters'],map_colors=colors)
    # Verified west Samgir portal destination: 100/637/493; return triggers at x638.
    if blocked[45*w+45]:raise ValueError('Original portal destination is blocked; investigate before importing')
    (output/'wilderness.json').write_text(json.dumps(result,separators=(',',':')))
    report=dict(source='chenmingbiao/stone-age @ 0c58fb6683a49a178a8ad845a8c296c2cb83bd81',map_sha256=hashlib.sha256(raw).hexdigest(),bounds=[ox,oy,w,h],portal_source='gmsv/data/npc/genout/100warp.create',missing_graphics=missing,images=len(used),objects=len(objects),walkable=sum(not b for b in blocked))
    (output/'wilderness-provenance.json').write_text(json.dumps(report,indent=2)); print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('source');parser.add_argument('--server-map',required=True);parser.add_argument('--output',default='client/assets/legacy');args=parser.parse_args();run(args.source,args.server_map,args.output)
