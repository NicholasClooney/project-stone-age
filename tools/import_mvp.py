"""Import source-backed Samgir shop, classic panels and starter items.

Uses original local archives unchanged. Shop stock, prices and progression belong
in game rules, not this art importer; MVP stock is not the original shop inventory.
"""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path
from import_legacy import Archive


def run(source, reference, output):
    output = Path(output)
    root = output / 'mvp'
    (root / 'ui').mkdir(parents=True, exist_ok=True)
    (root / 'images').mkdir(exist_ok=True)
    archive = Archive(source)
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    ui = {}
    numbers = [26040,26042,26043,26044,26045,26046,26052,26053,26054,26056,26058,26059,26060,26061,26070,26073,26076,26077,26091,26092,26093,26094,26095,26096,26097,26098,26130,26138,26139,26140]
    for number in numbers:
        bitmap = logical[number]
        archive.image(bitmap).save(root / 'ui' / f'{number}.png')
        entry = archive.entries[bitmap]
        ui[str(number)] = dict(bitmap=bitmap, path=f'ui/{number}.png', **{k:entry[k] for k in ('x','y','w','h')})
    reference = Path(reference)
    map_path = reference / 'gmsv/data/map/sainasu/samugiru/1002'
    raw = map_path.read_bytes()
    if raw[:6] != b'LS2MAP':
        raise ValueError('Expected LS2MAP')
    w,h = struct.unpack_from('>HH', raw, 40)
    size = w*h
    if len(raw) != 44 + size*4:
        raise ValueError('Incorrect interior length')
    tiles = struct.unpack_from(f'>{size}H', raw, 44)
    props = struct.unpack_from(f'>{size}H', raw, 44+size*2)
    ground,objects,missing = [],[],[]
    used = set()
    blocked = [False]*size
    for y in range(h):
        for x in range(w):
            i=y*w+x
            blocked[i] = tiles[i] in (0,1,2,5,6,9,10) or props[i] in (1,2,5,6,9,10)
            for value,is_prop in ((tiles[i],False),(props[i],True)):
                if value <= 99:
                    continue
                bitmap=archive.map_ids.get(value)
                if bitmap is None:
                    missing.append([x,y,value]);blocked[i]=True;continue
                entry=archive.entries[bitmap]
                used.add(bitmap)
                (objects if is_prop else ground).append([x,y,bitmap])
                if not is_prop and entry['hit'] in (0,2):
                    blocked[i]=entry['hit']==0
    for x,y,bitmap in objects:
        entry=archive.entries[bitmap]
        for dy in range(max(1,entry['ey'])):
            for dx in range(max(1,entry['ex'])):
                xx,yy=x+dx,y-dy
                if 0<=xx<w and 0<=yy<h and entry['hit'] in (0,2):
                    blocked[yy*w+xx]=entry['hit']==0
    for x,y,_ in missing:
        blocked[y*w+x]=True
    base=json.loads((output/'samgir.json').read_text())
    images=dict(base['images'])
    colors={}
    for bitmap in sorted(used):
        img=archive.image(bitmap)
        img.save(output/'images'/f'{bitmap}.png')
        entry=archive.entries[bitmap]
        images[str(bitmap)]={k:entry[k] for k in ('x','y','w','h','ex','ey','hit','priority')}
        colors[str(bitmap)]=list(img.convert('RGB').resize((1,1)).getpixel((0,0)))
    if any(blocked[y*w+x] for x,y in [(10,15),(11,15),(10,16),(16,15)]):
        raise ValueError('Original shop entry or safe spawn is blocked')
    data=dict(map_id=1002,name='萨姆吉尔的道具店',origin=[0,0],width=w,height=h,ground=ground,objects=objects,blocked=[int(v) for v in blocked],images=images,characters=base['characters'],map_colors=colors)
    (output/'shop.json').write_text(json.dumps(data,separators=(',',':')))
    merchant_bitmap=logical[16033]
    archive.image(merchant_bitmap).save(root/'images/merchant.png')
    e=archive.entries[merchant_bitmap]
    merchant=dict(name='萨姆吉尔的道具店',cell=[18,15],interaction_cell=[16,15],direction=6,graphic=16033,bitmap=merchant_bitmap,path='images/merchant.png',offset=[e['x'],e['y']],width=e['w'],height=e['h'],text='欢迎光临',buy_text='需要什么呢？',sell_text='要卖什么吗？')
    items={}
    for key,number,name,item_id in [('potion',23013,'耐久力回复药',1500),('club',20103,'小棍棒',100)]:
        bitmap=logical[number];e=archive.entries[bitmap]
        archive.image(bitmap).save(root/'images'/f'{key}.png')
        items[key]=dict(name=name,item_id=item_id,graphic=number,bitmap=bitmap,path=f'images/{key}.png',width=e['w'],height=e['h'])
    (root/'audio').mkdir(exist_ok=True)
    shutil.copyfile(archive.data/'bgm/sabgm_f0.wav',root/'audio/sabgm_f0.wav')
    manifest=dict(audio={'wilderness':'audio/sabgm_f0.wav'},ui=ui,items=items,merchant=merchant,shop=dict(path='../shop.json',map_id=1002,spawn=[11,15],portals=[dict(from_map=1000,cell=[67,108],to_map=1002,target=[10,15]),dict(from_map=1000,cell=[67,109],to_map=1002,target=[10,16]),dict(from_map=1002,cell=[10,15],to_map=1000,target=[67,108]),dict(from_map=1002,cell=[10,16],to_map=1000,target=[67,109])]),species=[dict(id='100250',name='乌力'),dict(id='100251',name='乌力乌力'),dict(id='100252',name='乌力斯坦')],provenance=dict(server_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',client_revision='1997fc20456dbda36d181b9680ae10bed2e9cdf9',map_sha256=hashlib.sha256(raw).hexdigest(),audio='gmsv/data/map/sainasu/sainasu props tone45 at633,493; system/map.cpp1004-1007 -> play_map_bgm; system/t_music.cpp3298-3300 tone45 -> bgm10; bgm_tbl2796 sabgm_f0.wav. Shop1002 has no music markers and keeps preceding village track.',missing_graphics=missing,npc='gmsv/data/npc/genout/shop_m.create: floor1002 merchant18,15 graphic16033',dialogue='gmsv/data/npc/genout/ss_1002_18_15',portals='gmsv/data/npc/genout/warp_y.create source lines27-29',ui='system/directdraw.cpp3962-3984 and systeminc/anim_tbl.h1650-1699',items='gmsv/data/itemset.txt item100 graphic20103; item1500 graphic23013',species='gmsv/data/enemybase.txt first3 rows; MVP encounter mix is designed, not verified original regional encounter table',limitations=['Shop stocks a narrow MVP selection; original shop1002 stock differs.','Safe entry spawn11,15 is one tile inside source portal10,15 to prevent immediate return.']))
    (root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'Imported shop {w}x{h}, {len(objects)} objects, {len(ui)} panels/buttons; missing graphics={len(missing)}')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--reference',default='references/chenmingbiao-stone-age')
    parser.add_argument('--output',default='client/assets/legacy')
    args=parser.parse_args()
    run(args.source,args.reference,args.output)
