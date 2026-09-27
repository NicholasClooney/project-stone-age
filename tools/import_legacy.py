"""Import a local classic StoneAge client into the Godot Samgir slice.

Reads 80-byte ADRN, RD/JSS-RLE graphics, 12-byte SPRADRN, SPR animation,
SAP BGR palette, and client DAT maps. Original inputs remain untouched.
Requires Pillow. Imported proprietary data stays local and is gitignored.
"""
from pathlib import Path
import argparse, hashlib, json, struct, shutil
from PIL import Image, ImageDraw

class Archive:
    def __init__(self, source):
        self.source = Path(source)
        self.data = self.source / 'data'
        self.adrn = (self.data / 'adrn_15.bin').read_bytes()
        if len(self.adrn) % 80: raise ValueError('ADRN size is not a multiple of 80')
        self.real = open(self.data / 'real_15.bin','rb')
        self.real_size = (self.data / 'real_15.bin').stat().st_size
        self.entries = {}
        self.map_ids = {}
        for at in range(0,len(self.adrn),80):
            ident,offset,length,x,y,w,h = struct.unpack_from('<IIIiiII',self.adrn,at)
            ex,ey,hit = struct.unpack_from('<BBH',self.adrn,at+28)
            map_id = struct.unpack_from('<I',self.adrn,at+76)[0]
            if not w or not h or w*h>16000000: continue
            entry = dict(id=ident,offset=offset,length=length,x=x,y=y,w=w,h=h,ex=ex,ey=ey,hit=hit%100,priority=hit//100,map_id=map_id)
            self.entries[ident]=entry
            if map_id: self.map_ids[map_id & 0xffff]=ident
        self.palette=[(0,0,0)]*256
        fixed=[(0,0,0),(128,0,0),(0,128,0),(128,128,0),(0,0,128),(128,0,128),(0,128,128),(192,192,192),(192,220,192),(166,202,240),(222,0,0),(255,95,0),(255,255,160),(0,95,210),(80,210,255),(40,225,40)]
        self.palette[:16]=fixed
        self.palette[240:]=[(245,195,150),(225,160,95),(195,125,70),(155,85,30),(70,65,55),(40,35,30),(255,251,240),(160,160,164),(128,128,128),(255,0,0),(0,255,0),(255,255,0),(0,0,255),(255,0,255),(0,255,255),(255,255,255)]
        pal=(self.data/'pal/Palet_1.sap').read_bytes()
        for i in range(224):
            b,g,r=pal[i*3:i*3+3];self.palette[i+16]=(r,g,b)
        self.palette[168]=(0,0,0)
        self.cache={}

    def image(self,ident):
        if ident in self.cache: return self.cache[ident]
        e=self.entries[ident]
        if e['offset']+e['length']>self.real_size: raise ValueError('Image points outside REAL')
        self.real.seek(e['offset']);raw=self.real.read(e['length'])
        if raw[:2]!=b'RD': raise ValueError(f'Image {ident}: invalid RD header')
        w,h=struct.unpack_from('<II',raw,4)
        if (w,h)!=(e['w'],e['h']): raise ValueError('RD/ADRN dimensions disagree')
        expected=w*h
        if raw[2]&1: pixels=decode_rle(raw[16:],expected)
        else:
            pixels=raw[16:16+expected]
            if len(pixels)!=expected: raise ValueError('Truncated raw image')
        img=Image.frombytes('P',(w,h),bytes(pixels))
        img.putpalette([v for rgb in self.palette for v in rgb])
        img.info['transparency']=0
        img=img.convert('RGBA').transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        self.cache[ident]=img
        return img

    def animations(self,ident):
        idx=(self.data/'spradrn_5.bin').read_bytes()
        raw=(self.data/'spr_4.bin').read_bytes()
        found=None
        for at in range(0,len(idx),12):
            number,offset,count=struct.unpack_from('<IIH',idx,at)
            if number==ident: found=(offset,count);break
        if found is None: raise ValueError(f'Sprite {ident} absent')
        at,count=found;result={}
        for _ in range(count):
            direction,action,duration,frames=struct.unpack_from('<HHII',raw,at);at+=12
            if frames>1000: raise ValueError('Unreasonable frame count')
            sequence=[]
            for _ in range(frames):
                bmp,x,y,sound=struct.unpack_from('<IhhH',raw,at);at+=10
                sequence.append(dict(image=bmp,x=x,y=y,sound=sound))
            if action in (3,4,5,6,7):
                result[f'{action}_{direction}']=dict(duration_ms=duration,frames=sequence)
        return result


def decode_rle(data,expected):
    out=bytearray(); at=0
    while at<len(data) and len(out)<expected:
        command=data[at];at+=1
        kind=command>>4; count=command&15
        if kind not in (0,1,2,8,9,10,12,13,14): raise ValueError(f'Unknown RLE command {kind:x}')
        repeated=kind in (8,9,10);transparent=kind in (12,13,14)
        color=0
        if repeated:
            if at>=len(data):raise ValueError('Truncated RLE color')
            color=data[at];at+=1
        extra=kind%4
        if at+extra>len(data):raise ValueError('Truncated RLE count')
        for _ in range(extra):count=count*256+data[at];at+=1
        if len(out)+count>expected:raise ValueError('RLE overrun')
        if repeated or transparent:out.extend(bytes([color])*count)
        else:
            if at+count>len(data):raise ValueError('Truncated RLE literal')
            out.extend(data[at:at+count]);at+=count
    if len(out)!=expected:raise ValueError(f'Incomplete RLE: {len(out)}/{expected}')
    return out


def run(source,output,server_map=None):
    archive=Archive(source); output=Path(output);(output/'images').mkdir(parents=True,exist_ok=True)
    raw=(Path(source)/'map/1000.DAT').read_bytes()
    w,h=struct.unpack_from('<II',raw);size=w*h
    if not 0<w<=1000 or not 0<h<=1000 or len(raw)!=8+size*6:raise ValueError('Invalid map dimensions/length')
    tiles=list(struct.unpack_from(f'<{size}H',raw,8)); props=list(struct.unpack_from(f'<{size}H',raw,8+size*2));events=list(struct.unpack_from(f'<{size}H',raw,8+size*4))
    map_source = 'client DAT'
    if server_map:
        server=Path(server_map).read_bytes()
        if server[:6]!=b'LS2MAP' or struct.unpack_from('>HH',server,40)!=(w,h) or len(server)!=44+size*4:raise ValueError('Invalid LS2MAP file')
        tiles=list(struct.unpack_from(f'>{size}H',server,44))
        props=list(struct.unpack_from(f'>{size}H',server,44+size*2))
        events=[0x8000]*size
        map_source='chenmingbiao/stone-age: gmsv/data/map/sainasu/samugiru/samugiru'
    used=set();cells=[];objects=[];missing=[];blocked=[False]*size
    for y in range(h):
        for x in range(w):
            i=y*w+x;tile=tiles[i];part=props[i]
            if not (events[i]&0x8000) or tile in (0,1,2,5,6,9,10) or part in (1,2,5,6,9,10):blocked[i]=True
            for value,is_prop in [(tile,False),(part,True)]:
                if value<=99:continue
                ident=archive.map_ids.get(value)
                if ident is None:
                    missing.append(dict(id=value,x=x,y=y,layer='objects' if is_prop else 'ground'))
                    blocked[i]=True
                    continue
                used.add(ident);entry=archive.entries[ident]
                (objects if is_prop else cells).append([x,y,ident])
                if is_prop:
                    for dy in range(max(1,entry['ey'])):
                        for dx in range(max(1,entry['ex'])):
                            xx,yy=x+dx,y-dy
                            if 0<=xx<w and 0<=yy<h and entry['hit'] in (0,2):blocked[yy*w+xx]=entry['hit']==0
                elif entry['hit'] in (0,2):blocked[i]=entry['hit']==0
    # Reapply object footprints after ground flags, preserving bridge overrides.
    for x,y,ident in objects:
        entry=archive.entries[ident]
        for dy in range(max(1,entry['ey'])):
            for dx in range(max(1,entry['ex'])):
                xx,yy=x+dx,y-dy
                if 0<=xx<w and 0<=yy<h and entry['hit'] in (0,2):blocked[yy*w+xx]=entry['hit']==0
    characters={}
    for sprite in (100000,100005,100010):
        animations=archive.animations(sprite)
        characters[str(sprite)]=animations
        for animation in animations.values():
            used.update(f['image'] for f in animation['frames'])
    metadata={}
    for ident in sorted(used):
        archive.image(ident).save(output/'images'/f'{ident}.png')
        e=archive.entries[ident]
        metadata[str(ident)]={k:e[k] for k in ('x','y','w','h','ex','ey','hit','priority')}
    content=dict(map_id=1000,width=w,height=h,ground=cells,objects=objects,blocked=[int(x) for x in blocked],images=metadata,characters=characters)
    (output/'samgir.json').write_text(json.dumps(content,separators=(',',':')))
    # Full-map preview is research output, never used as a stand-in for live map rendering.
    preview=Image.new('RGBA',((w+h)*32+500,(w+h)*24+500),(30,42,40,255))
    for group in (cells,sorted(objects,key=lambda v:(v[1]-v[0],v[0]+v[1]))):
        for x,y,ident in group:
            e=archive.entries[ident];preview.alpha_composite(archive.image(ident),(int((x+y)*32+e['x']+250),int((y-x)*24+w*24+e['y']+250)))
    preview.thumbnail((1800,1400));preview.convert('RGB').save(output/'map-preview.jpg')
    for file in ['bgm/sabgm_t0.wav','bgm/sabgm_t1.wav','se/sas_01.wav','se/sas_02.wav']:
        p=Path(source)/'data'/file
        if p.exists(): shutil.copyfile(p,output/p.name)
    report=dict(source='99ds.com StoneAge 2.5 client package SA2.5-20260823',map_source=map_source,map_sha256=hashlib.sha256(server if server_map else raw).hexdigest(),palette_sha256=hashlib.sha256((archive.data/'pal/Palet_1.sap').read_bytes()).hexdigest(),missing_graphics=missing,images=len(used),ground_cells=len(cells),objects=len(objects),walkable=sum(not v for v in blocked),sprite_ids=list(characters))
    (output/'provenance.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('source');parser.add_argument('--output',default='client/assets/legacy');parser.add_argument('--server-map');args=parser.parse_args()
    run(args.source,args.output,args.server_map)
