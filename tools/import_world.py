"""Import original towns/interiors and explicitly listed developer training areas.

Read-only legacy inputs. Unavailable graphics remain blocked. Original warp
coordinates are retained; developer spawns are selected from walkable cells.
"""
import argparse
from collections import Counter, deque
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
from import_legacy import Archive

VILLAGES = {1000, 2000, 3000, 4000}
TOWNS = VILLAGES | {1100, 1300, 1400, 3100, 3200, 3300, 3400, 5000, 5100}
# Reviewed ordinary Giru buildings only. The same north directory also contains
# quest-controlled snake caves and room 5107, which must stay excluded.
GIRU_SETTLEMENT_MAPS = {5000, 5001, 5003, 5005, 5100, 5101, 5103, 5105, 5106}
# Reviewed ordinary settlement directories only; never infer access from map IDs.
ORDINARY_DIRECTORIES = {'sainasu/hotoru', 'sainasu/katan', 'sainasu/kuo',
                        'jyaruga/tamtam', 'jyaruga/toto', 'jyaruga/ururi', 'jyaruga/kikuku'}
CORE = VILLAGES | {100, 200, 1100, 10201, 10202, 10203}
# Explicit developer destinations only: no quest entrances or script traversal.
DEV_TRAINING_MAPS = {300, 400, 500} | set(range(10001, 10007)) | set(range(31701, 31707)) | set(range(32001, 32021))
MUSIC = {40: 'sabgm_t0.wav', 41: 'sabgm_t1.wav', 44: 'sabgm_d2.wav', 45: 'sabgm_f0.wav', 46: 'sabgm_f1.wav'}


def read_map(path):
    raw = Path(path).read_bytes()
    if len(raw) < 44 or raw[:6] != b'LS2MAP':
        raise ValueError(f'Invalid LS2MAP: {path}')
    ident = struct.unpack_from('>H', raw, 6)[0]
    w, h = struct.unpack_from('>HH', raw, 40)
    if not w or not h or len(raw) != 44 + w*h*4:
        raise ValueError(f'Invalid LS2MAP dimensions/length: {path}')
    name = raw[8:40].split(b'\0')[0].decode('gbk', errors='replace').split('|')[0]
    return ident, name, w, h, struct.unpack_from(f'>{w*h}H', raw, 44), struct.unpack_from(f'>{w*h}H', raw, 44+w*h*2), raw


def read_portals(root):
    result = {}
    for path in sorted(Path(root).glob('*.create')):
        for match in re.finditer(r'\{([^}]+)\}', path.read_text(errors='replace')):
            block = match[1]
            floor = re.search(r'floorid=(\d+)', block)
            corner = re.search(r'borncorner=(\d+),(\d+),(\d+),(\d+)', block)
            target = re.search(r'enemy=npcgen_warp\|(\d+)\|(\d+)\|(\d+)', block)
            if not (floor and corner and target):
                continue
            x1,y1,x2,y2 = map(int, corner.groups())
            for y in range(y1,y2+1):
                for x in range(x1,x2+1):
                    p = dict(from_map=int(floor[1]), cell=[x,y], to_map=int(target[1]), target=[int(target[2]),int(target[3])], source=f'{path.name}:{path.read_text(errors="replace")[:match.start()].count(chr(10))+1}')
                    key = (p['from_map'], x,y,p['to_map'],*p['target'])
                    result[key] = p
    return list(result.values())


def select_connected_maps(map_paths, portals):
    """Expand only through original unconditional warps into reviewed settlements.

    No dungeon/family/quest script traversal, synthetic links or gate bypasses.
    Existing core (including its implemented permit gate) is preserved.
    """
    selected = CORE | {300} | {p['to_map'] for p in portals if p['from_map'] in VILLAGES}
    while True:
        additions = {p['to_map'] for p in portals
                     if p['from_map'] in selected and p['to_map'] in map_paths
                     and ('/'.join(map_paths[p['to_map']].parts[-3:-1]) in ORDINARY_DIRECTORIES
                          or p['to_map'] in GIRU_SETTLEMENT_MAPS)}
        if additions <= selected:
            return selected
        selected |= additions


def ordinary_portals(portals, ordinary):
    """DEV imports must not silently open quest-controlled routes."""
    return [p for p in portals if p['from_map'] in ordinary and p['to_map'] in ordinary
            and (300 not in (p['from_map'], p['to_map'])
                 or (p['from_map'] in (5000, 5100) or p['to_map'] in (5000, 5100)))]


def settlement_owner(ident, map_paths):
    """Use reviewed town source folders, never numerical map-id ranges."""
    path = map_paths[ident]
    return next((town for town in sorted(TOWNS)
                 if town in map_paths and map_paths[town].parent == path.parent), 0)


def disable_conflicting_portals(portals):
    """Never select one of several contradictory source warps silently."""
    destinations={}; conflicting_warps=set()
    for p in portals:
        key=(p['from_map'],*p['cell'])
        value=(p['to_map'],*p['target'])
        if key in destinations and destinations[key]!=value:conflicting_warps.add(key)
        destinations[key]=value
    for p in portals:
        if (p['from_map'],*p['cell']) in conflicting_warps:
            p.update(disabled=True,reason='Conflicting original warp destinations; requires source review')


def excluded_reason(path):
    if path is None:
        return 'Original destination map missing'
    if 'dungeon' in path.parts:
        return 'Dungeon / gated progression deferred with quests'
    if any(part in path.parts for part in ('family', 'quiz', 'king', 'EDEN')):
        return 'Special area / quest mechanics deferred'
    return 'Destination outside reviewed ordinary connected settlements'


def convert(archive, parsed):
    ident,name,w,h,tiles,props,_ = parsed
    ground,objects,missing,tones = [],[],[],[]
    used=set(); blocked=[False]*(w*h)
    for i,(tile,prop) in enumerate(zip(tiles,props)):
        x,y=i%w,i//w
        blocked[i]=tile in (0,1,2,5,6,9,10) or prop in (1,2,5,6,9,10)
        if prop in MUSIC: tones.append(dict(cell=[x,y],tone=prop,music='world/audio/'+MUSIC[prop]))
        for value,is_prop in ((tile,False),(prop,True)):
            if value<=99: continue
            bitmap=archive.map_ids.get(value)
            if bitmap is None:
                missing.append([x,y,value]); continue
            used.add(bitmap); entry=archive.entries[bitmap]
            (objects if is_prop else ground).append([x,y,bitmap])
            if not is_prop and entry['hit'] in (0,2): blocked[i]=entry['hit']==0
    for x,y,bitmap in objects:
        e=archive.entries[bitmap]
        for dy in range(max(1,e['ey'])):
            for dx in range(max(1,e['ex'])):
                xx,yy=x+dx,y-dy
                if 0<=xx<w and 0<=yy<h and e['hit'] in (0,2):blocked[yy*w+xx]=e['hit']==0
    for x,y,_ in missing:blocked[y*w+x]=True
    return dict(map_id=ident,name=name,origin=[0,0],width=w,height=h,ground=ground,objects=objects,blocked=list(map(int,blocked)),music_markers=tones),used,missing


def safe_spawn(data, preferred, forbidden=(), reachable=None):
    w,h=data['width'],data['height']; forbidden=set(map(tuple,forbidden))
    px,py=preferred; px=max(0,min(w-1,px));py=max(0,min(h-1,py))
    todo=deque([(px,py)]);seen={(px,py)}
    while todo:
        x,y=todo.popleft()
        if not data['blocked'][y*w+x] and (x,y) not in forbidden and (reachable is None or reachable[y*w+x]):return [x,y]
        for dx,dy in ((1,0),(0,1),(-1,0),(0,-1)):
            p=(x+dx,y+dy)
            if 0<=p[0]<w and 0<=p[1]<h and p not in seen:seen.add(p);todo.append(p)
    raise ValueError(f'No safe spawn in map {data["map_id"]}')



def reachable_cells(data, spawn):
    """Conservative cardinal flood: success guarantees a walkable route."""
    w,h=data['width'],data['height'];blocked=data['blocked'];x,y=spawn
    seen=bytearray(w*h);seen[y*w+x]=1;todo=deque([y*w+x])
    while todo:
        i=todo.popleft();x,y=i%w,i//w
        for nx,ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
            if 0<=nx<w and 0<=ny<h:
                j=ny*w+nx
                if not seen[j] and not blocked[j]:seen[j]=1;todo.append(j)
    return seen


def import_residents(archive, reference, root):
    source=reference/'gmsv/data/npc/genout'; residents=[]
    (root/'npcs').mkdir(exist_ok=True)
    logical={e['map_id']:e['id'] for e in archive.entries.values() if e['map_id']}
    for village in sorted(VILLAGES):
        path=source/f'{village}npc_m.create'
        for match in re.finditer(r'\{([^}]+)\}',path.read_text(encoding='gb18030')):
            fields=dict(line.strip().split('=',1) for line in match[1].splitlines() if '=' in line)
            if not fields.get('enemy','').startswith('npcgen_man|file:'):continue
            if int(fields['floorid'])!=village:continue
            x,y,x2,y2=map(int,fields['borncorner'].split(','))
            if (x,y)!=(x2,y2):raise ValueError('Moving resident definition needs explicit support')
            if village==1000 and (x,y)==(93,72):continue
            dialogue=reference/'gmsv/data/npc'/fields['enemy'].split('file:',1)[1]
            lines=[text.strip() for text in dialogue.read_text(encoding='gb18030').strip().split(',') if text.strip()]
            graphic=int(fields['graphicname']);bitmap=logical[graphic];e=archive.entries[bitmap]
            archive.image(bitmap).save(root/'npcs'/f'{graphic}.png')
            residents.append(dict(map_id=village,role='resident',cell=[x,y],name=fields['name'],graphic=graphic,path=f'world/npcs/{graphic}.png',offset=[e['x'],e['y']],facing=int(fields['dir']),text=lines[0] if lines else '',dialogues=lines,source=str(path.relative_to(reference)),dialogue_source=str(dialogue.relative_to(reference))))
    for map_id,cell,graphic,name,role,destination in [
        (1100,[86,107],16018,'贩卖通行证','vendor',None),
        (4000,[99,85],16018,'通行证贩卖','vendor',None),
        (10202,[22,28],16205,'海底洞窟关卡','gate',[21,33]),
        (10202,[22,32],16208,'海底洞窟关卡','gate',[21,27]),
    ]:
        bitmap=logical[graphic];e=archive.entries[bitmap]
        archive.image(bitmap).save(root/'npcs'/f'{graphic}.png')
        npc=dict(map_id=map_id,cell=cell,graphic=graphic,name=name,role=role,destination=destination,path=f'world/npcs/{graphic}.png',offset=[e['x'],e['y']],facing=6,text='',source='gmsv/data/npc/genout/'+('10200npc.create' if role=='gate' else 'shop_m.create' if map_id==1100 else 'shop_m2.create'))
        dialogue=source/(f'wpm_{map_id}_{cell[0]}_{cell[1]}' if role=='gate' else f'ss_{map_id}_{cell[0]}_{cell[1]}')
        fields=dict(line.split(':',1) for line in dialogue.read_text(encoding='gb18030').splitlines() if ':' in line)
        npc['text']=fields['PayMsg' if role=='gate' else 'buy_main'].replace('\\n','\n').strip()
        npc['free_text']=fields.get('FreeMsg','').replace('\\n','\n').strip()
        npc['dialogue_source']=str(dialogue.relative_to(reference))
        residents.append(npc)
    from import_dana_npcs import import_residents as dana_residents
    residents.extend(dana_residents(archive, reference, root))
    return residents


def run(source, reference, output):
    reference=Path(reference); output=Path(output); root=output/'world'
    root.mkdir(parents=True,exist_ok=True);(root/'audio').mkdir(exist_ok=True);(output/'images').mkdir(exist_ok=True)
    all_portals=read_portals(reference/'gmsv/data/npc/genout')
    maps={}; conflicting=set()
    for path in sorted((reference/'gmsv/data/map').rglob('*')):
        if path.is_file() and path.read_bytes()[:6]==b'LS2MAP':
            ident=struct.unpack_from('>H',path.read_bytes(),6)[0]
            if ident in maps and maps[ident].read_bytes()!=path.read_bytes():conflicting.add(ident)
            maps[ident]=path
    ordinary=select_connected_maps(maps,all_portals)
    selected=ordinary | DEV_TRAINING_MAPS
    if selected & conflicting:raise ValueError(f'Conflicting selected map IDs: {sorted(selected & conflicting)}')
    absent=selected-maps.keys()
    if absent:raise ValueError(f'Missing original maps: {absent}')
    # Preserve the existing exploration graph. Extra areas are DEV-only until
    # their entrances, quest gates and progression are restored explicitly.
    portals=ordinary_portals(all_portals, ordinary)
    disable_conflicting_portals(portals)
    unsupported=[dict(p, reason=excluded_reason(maps.get(p['to_map']))) for p in all_portals if p['from_map'] in ordinary and p['to_map'] not in ordinary]
    archive=Archive(source);base=json.loads((output/'samgir.json').read_text()); images={};colors={}; metadata={}; reports={};blocked_portals=[]
    residents=import_residents(archive,reference,root)
    preferred={100:[637,493],200:[570,377],1000:[89,73],2000:[74,56],3000:[84,100],4000:[76,90]}
    for ident in sorted(selected):
        parsed=read_map(maps[ident]);data,used,missing=convert(archive,parsed)
        for bitmap in sorted(used):
            key=str(bitmap)
            if key not in images:
                img=archive.image(bitmap);img.save(output/'images'/f'{bitmap}.png')
                e=archive.entries[bitmap];images[key]={k:e[k] for k in ('x','y','w','h','ex','ey','hit','priority')}
                colors[key]=list(img.convert('RGB').resize((1,1)).getpixel((0,0)))
        data['images']={**base['images'],**{str(v):images[str(v)] for v in used}};data['map_colors']={str(v):colors[str(v)] for v in used};data['characters']=base['characters']
        exits=[p['cell'] for p in portals if p['from_map']==ident]
        incoming=[p['target'] for p in portals if p['to_map']==ident]
        # Keep development destinations inside the original arrival component;
        # nearest walkable alone can select an isolated decorative island.
        entrance=safe_spawn(data,incoming[0] if incoming else [data['width']//2,data['height']//2])
        arrival_region=reachable_cells(data,entrance)
        occupied=[npc['cell'] for npc in residents if npc['map_id']==ident]
        spawn=safe_spawn(data,preferred.get(ident,entrance),exits+occupied,arrival_region)
        kind='training' if ident in DEV_TRAINING_MAPS else 'village' if ident in TOWNS else 'wilderness' if ident in (100,200) else 'interior'
        tones=Counter(m['tone'] for m in data['music_markers'])
        music='world/audio/'+MUSIC[tones.most_common(1)[0][0]] if tones else None
        metadata[str(ident)]=dict(path=f'world/{ident}.json',name=data['name'],width=data['width'],height=data['height'],kind=kind,spawn=spawn,music=music)
        owner=settlement_owner(ident,maps)
        if owner:metadata[str(ident)]['village_id']=owner
        if ident in DEV_TRAINING_MAPS:metadata[str(ident)]['dev_only']=True
        for p in portals:
            points=[]
            if p['from_map']==ident:points.append(('cell',p['cell']))
            if p['to_map']==ident:points.append(('target',p['target']))
            for field,(x,y) in points:
                if not (0<=x<data['width'] and 0<=y<data['height']):raise ValueError(f'Warp outside map: {p}')
                if data['blocked'][y*data['width']+x]:blocked_portals.append(dict(map_id=ident,field=field,portal=p))
        (root/f'{ident}.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')))
        reachable=reachable_cells(data,spawn)
        exit_coverage={}
        for p in portals:
            if p['from_map']==ident:
                key=str(p['to_map']);exit_coverage.setdefault(key,dict(reachable=0,unreachable=0));x,y=p['cell']
                exit_coverage[key]['reachable' if reachable[y*data['width']+x] else 'unreachable']+=1
        if ident in TOWNS and not all(v['reachable'] for v in exit_coverage.values()):raise ValueError(f'Village spawn cannot reach exits: {ident} {exit_coverage}')
        reports[str(ident)]=dict(reachable_cells=sum(reachable),exit_coverage=exit_coverage,source=str(maps[ident].relative_to(reference)),sha256=hashlib.sha256(parsed[-1]).hexdigest(),missing_graphics=missing,walkable=data['blocked'].count(0),images=len(used),objects=len(data['objects']))
        print(f'{ident} {data["name"]} {data["width"]}x{data["height"]} missing={len(missing)} spawn={spawn}',flush=True)
    for name in set(MUSIC.values()):shutil.copyfile(archive.data/'bgm'/name,root/'audio'/name)
    blocked_keys={(p['portal']['from_map'],*p['portal']['cell']) for p in blocked_portals}
    for p in portals:
        if (p['from_map'],*p['cell']) in blocked_keys:p.update(disabled=True,reason='Original warp endpoint collides in available resource revision')
    manifest=dict(maps=metadata,residents=residents,portals=portals,teleports=[dict(map_id=i,name=metadata[str(i)]['name'],cell=metadata[str(i)]['spawn']) for i in [1000,2000,3000,4000,100,200]+sorted(TOWNS-VILLAGES)],provenance=dict(server_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',maps=reports,unsupported_portals=unsupported,blocked_portals=blocked_portals,music='Original map object markers40/41/44/45/46; client system/t_music.cpp play_map_bgm and bgm_tbl. Interiors with no marker preserve preceding track.',limitations=['Original cross-island tunnel imported; its floor10202 quest gate requires original passage permit; runtime must implement gate or label developer bypass.','Imported interiors restore scenery and original doors only; no invented NPC services or quests.','Only reviewed settlements connected by original unconditional warps are expanded. New interiors provide scenery and doors, not NPC services. Dungeons, special areas and quest-dependent routes are deferred; unsupported exits include reasons.', 'Explicit dev_only training maps restore scenery and ordinary source encounters. Giru 300 additionally has reviewed original doors to villages 5000/5100 and their ordinary interiors; other training entrances, quest gates, NPCs, bosses and internal travel links are not restored.']))
    (root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(metadata)} maps, {len(portals)} portals, {len(blocked_portals)} blocked endpoints, {len(images)} images')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source');parser.add_argument('--reference',default='references/chenmingbiao-stone-age');parser.add_argument('--output',default='client/assets/legacy');args=parser.parse_args();run(args.source,args.reference,args.output)
