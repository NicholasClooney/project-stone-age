"""Import original settlements, reviewed scenic caves and developer training areas.

Read-only legacy inputs. Unavailable graphics remain blocked. Original warp
coordinates are retained; developer spawns are selected from walkable cells.
"""
import argparse
from collections import Counter, deque
import hashlib
import json
from pathlib import Path
import re
import struct
from import_legacy import Archive
from map_file import save_map
from world_review import load_reviews, read_reviewed_portals, merge_portals
from world_fallback import FallbackArchive
from world_components import finalize_reviewed_maps

from import_brothers_quests import MAPS as BROTHERS_MAPS, SPEC as BROTHERS_SPEC
QUEST_MAPS = set(BROTHERS_MAPS)
REGION_REVIEWS = load_reviews()
REVIEWED_REGION_MAPS = {i for r in REGION_REVIEWS.values() for i in r["maps"] if str(i) not in r.get("deferred",{})}
REVIEWED_INTERIORS = {i for r in REGION_REVIEWS.values() for i in r.get("interiors",[])}

VILLAGES = {1000, 2000, 3000, 4000}
TOWNS = VILLAGES | {1100, 1300, 1400, 3100, 3200, 3300, 3400, 5000, 5100}
TOWNS |= {i for r in REGION_REVIEWS.values() for i in r.get("towns",[])}
# Reviewed ordinary Giru buildings only. The same north directory also contains
# quest-controlled snake caves and room 5107, which must stay excluded.
GIRU_SETTLEMENT_MAPS = {5000, 5001, 5003, 5005, 5100, 5101, 5103, 5105, 5106}
# Reviewed ordinary settlement directories only; never infer access from map IDs.
ORDINARY_DIRECTORIES = {'sainasu/hotoru', 'sainasu/katan', 'sainasu/kuo',
                        'jyaruga/tamtam', 'jyaruga/toto', 'jyaruga/ururi', 'jyaruga/kikuku'}
CORE = VILLAGES | {100, 200, 1100, 10201, 10202, 10203}
# Explicit developer destinations only: no quest entrances or script traversal.
DEV_TRAINING_MAPS = {300, 400, 500} | set(range(10001, 10007)) | set(range(31701, 31707)) | set(range(32001, 32021))
# Reviewed Jyaruga scenery; named service/quest rooms remain excluded.
JYARUGA_SCENIC_MAPS = (set(range(20001, 20014)) | set(range(20101, 20106))
    | set(range(20301, 20310)) | set(range(20401, 20407))
    | set(range(20501, 20508)) | set(range(20601, 20608))
    | set(range(20701, 20711)) | set(range(20801, 20808))
    | set(range(20901, 20904)) | set(range(21001, 21017))
    | {21103, 21106, 21108, 21109, 21110, 21111, 21112, 21113}
    | set(range(21201, 21216)) | set(range(21301, 21316)))
# Only these reviewed warpman scripts may bypass original conditions.
SCENIC_GATE_SCRIPTS = {
    'wpm_20604_11_53', 'wpm_20605_51_4', 'wpm_20606_9_23',
    'wpm_20807_11_37', 'wpm_200_337_653', 'wpm_20901_21_13',
    'wpm_20901_16_17', 'wpm_20301_200_39', 'wpm_21301_8_3',
    'wpm_200_73_696', 'wpm_21308_20_10', 'wpm_200_316_711',
    'wpm_200_359_671', 'wpm_200_358_671', 'wpm_21003_34_10',
}


def read_scenic_gates(root):
    """Explicit scenery convenience, retaining original cells/destinations."""
    result = []
    for path in sorted(Path(root).glob('*.create')):
        for match in re.finditer(r'\{([^}]+)\}', path.read_text(errors='replace')):
            block = match[1]
            script = re.search(r'enemy=npcgen_warpman\|file:genout/([^\s]+)', block)
            if not script or script[1] not in SCENIC_GATE_SCRIPTS:
                continue
            fields = (Path(root) / script[1]).read_text(encoding='gb18030')
            target = re.search(r'^WARP:(\d+),(\d+),(\d+)', fields, re.M)
            floor = re.search(r'floorid=(\d+)', block)
            corner = re.search(r'borncorner=(\d+),(\d+),(\d+),(\d+)', block)
            if not (target and floor and corner):
                raise ValueError(f'Invalid reviewed scenery gate: {script[1]}')
            x,y,x2,y2 = map(int, corner.groups())
            if (x,y) != (x2,y2):
                raise ValueError(f'Non-point scenery gate: {script[1]}')
            result.append(dict(from_map=int(floor[1]), cell=[x,y],
                to_map=int(target[1]), target=[int(target[2]),int(target[3])],
                source=f'{path.name}:{path.read_text(errors="replace")[:match.start()].count(chr(10))+1}',
                gate_source='genout/'+script[1], convenience='原版需要任务或NPC检查，这里直接开放'))
    return result


MUSIC = {40: 'sabgm_t0.wav', 41: 'sabgm_t1.wav', 44: 'sabgm_d2.wav', 45: 'sabgm_f0.wav', 46: 'sabgm_f1.wav'}


def read_map(path):
    raw = Path(path).read_bytes()
    if len(raw) < 44 or raw[:6] != b'LS2MAP':
        raise ValueError(f'Invalid LS2MAP: {path}')
    ident = struct.unpack_from('>H', raw, 6)[0]
    w, h = struct.unpack_from('>HH', raw, 40)
    # The original server reads exactly two 400-short layers for this source.
    seimu_padding = (ident == 40 and (w, h) == (20, 20)
                     and len(raw) == 1645 and raw[-1:] == b'\0'
                     and hashlib.sha256(raw).hexdigest() ==
                     '75eef0bbf69f257b7f3705a1fef98242a4cf2d375cb8838f87a5411297fd9727')
    if not w or not h or (len(raw) != 44 + w*h*4 and not seimu_padding):
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
            target = re.search(r'enemy=npcgen_warp\|(\d+)\|(\d+)\|(\d+)(?:\|([A-Z]+))?\s*$', block, re.M)
            if not (floor and corner and target):
                continue
            x1,y1,x2,y2 = map(int, corner.groups())
            for y in range(y1,y2+1):
                for x in range(x1,x2+1):
                    p = dict(from_map=int(floor[1]), cell=[x,y], to_map=int(target[1]), target=[int(target[2]),int(target[3])], source=f'{path.name}:{path.read_text(errors="replace")[:match.start()].count(chr(10))+1}')
                    if target[4]:p['source_time_suffix']=target[4]
                    key = (p['from_map'], x,y,p['to_map'],*p['target'])
                    result[key] = p
    return list(result.values())


def select_connected_maps(map_paths, portals):
    """Expand through original warps into reviewed settlements and scenery.

    Only explicitly reviewed scenery gates bypass NPC checks; no general script traversal.
    Existing core (including its implemented permit gate) is preserved.
    """
    selected = CORE | {300, 400} | {p['to_map'] for p in portals if p['from_map'] in VILLAGES}
    while True:
        additions = {p['to_map'] for p in portals
                     if p['from_map'] in selected and p['to_map'] in map_paths
                     and ('/'.join(map_paths[p['to_map']].parts[-3:-1]) in ORDINARY_DIRECTORIES
                          or p['to_map'] in GIRU_SETTLEMENT_MAPS
                          or p['to_map'] in JYARUGA_SCENIC_MAPS
                          or p['to_map'] in REVIEWED_REGION_MAPS)}
        if additions <= selected:
            return selected
        selected |= additions


def ordinary_portals(portals, ordinary, quest_maps=None):
    """Only selected ordinary/scenic maps get walking portals."""
    quest_maps = QUEST_MAPS if quest_maps is None else quest_maps
    return [p for p in portals if p['from_map'] in ordinary and p['to_map'] in ordinary
            and (300 not in (p['from_map'], p['to_map'])
                 or (p['from_map'] in (5000, 5100) or p['to_map'] in (5000, 5100))
                 or p['from_map'] in REVIEWED_REGION_MAPS or p['to_map'] in REVIEWED_REGION_MAPS
                 or p['from_map'] in quest_maps or p['to_map'] in quest_maps)]


def require_seimu_permits(portals):
    """Conservative profile permit gate on every direction of the three sea routes.

    Original outgoing NPCs have FREE empty / MONEY 300; fee dialogue is not
    restored. Incoming ordinary doors must also be gated to prevent crossing
    between islands via the common checkpoint from any starting island.
    """
    for portal in portals:
        if (portal['from_map'] == 40 and portal['to_map'] in (31301,31401,31501)
                or portal['to_map'] == 40 and portal['from_map'] in (31301,31401,31501)):
            portal['requires_travel_pass'] = True
            portal.pop('convenience',None)


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


# Duplicate original records at reviewed scenery doors. Pick an existing
# original destination, rather than moving endpoints or enabling all variants.
SCENIC_DOOR_CHOICES = {
    (20301,18,6):(200,421,577), (20301,281,125):(200,501,647),
    (200,285,926):(20601,9,59), (200,432,536):(20701,0,23),
    (21215,26,11):(21315,52,59), (21315,53,59):(21215,26,11),
    (21016,13,21):(21011,5,4),
    (300,343,191):(31701,29,49),
    (300,239,98):(31901,0,43), (31901,71,6):(31902,0,4),
}


def review_scenic_doors(portals):
    choices=dict(SCENIC_DOOR_CHOICES)
    for review in REGION_REVIEWS.values():
        for record in review.get('door_choices',[]):
            choices[tuple(record['from'])]=tuple(record['to'])
    for p in portals:
        choice=choices.get((p['from_map'],*p['cell']))
        if choice is None:
            continue
        if (p['to_map'],*p['target']) == choice:
            p.pop('disabled',None)
            p.pop('reason',None)
            p['convenience']='重复原版入口采用已核对的一个原始落点'
        else:
            p.update(disabled=True,reason='Reviewed scenery door uses another original destination')


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
        # Ground 60-79 are invisible walls: never drawn, but their bitmap's
        # hit flag still counts (client map.cpp readHitMap: tile > CG_INVISIBLE
        # or 60 <= tile <= 79 reads realGetHitFlag).
        if 60<=tile<=79:
            bitmap=archive.map_ids.get(tile)
            if bitmap is not None and archive.entries[bitmap]['hit'] in (0,2):blocked[i]=archive.entries[bitmap]['hit']==0
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


def run(source, reference, output, fallback_source=None):
    reference=Path(reference); output=Path(output); root=output/'world'
    root.mkdir(parents=True,exist_ok=True);(output/'images').mkdir(exist_ok=True)
    from quest_import_common import module_world_reviews, staged_module_world_reviews, apply_module_portal_choices
    modules = module_world_reviews(reference)
    from prison_world import load_review, restrict_portals
    prison_review = load_review(reference)
    modules.append(prison_review)
    staged = staged_module_world_reviews(reference)
    staged_maps = {int(i) for review in staged for i in review.get("map_sources", {})}
    quest_maps = QUEST_MAPS | {int(ident) for module in modules for ident in module.get('map_sources', {})}
    all_portals=read_portals(reference/'gmsv/data/npc/genout')
    all_portals.extend(read_scenic_gates(reference/'gmsv/data/npc/genout'))
    from transmigration_foundation import portals as module_portals
    all_portals=merge_portals(all_portals+read_reviewed_portals(reference,REGION_REVIEWS)+module_portals(reference,modules))
    staged_portals=module_portals(reference,staged)
    all_portals=restrict_portals(all_portals, prison_review)
    all_portals=apply_module_portal_choices(all_portals, modules)
    from quest_time_gates import apply_time_gates
    all_portals=apply_time_gates(all_portals,modules)
    # Restored NPC gates now transact through original_quests; scenery portals
    # must not bypass their item/flag checks.
    restored_scripts=set(json.loads(BROTHERS_SPEC.read_text())["scripts"])
    restored_scripts.update(script for module in modules for script in module.get("restored_scripts", []))
    all_portals=[p for p in all_portals if p.get("gate_source") not in restored_scripts]
    maps={}; variants={}; conflicting=set()
    for path in sorted((reference/'gmsv/data/map').rglob('*')):
        if path.is_file() and path.read_bytes()[:6]==b'LS2MAP':
            ident=struct.unpack_from('>H',path.read_bytes(),6)[0]
            variants.setdefault(ident,[]).append(path)
            if ident in maps and maps[ident].read_bytes()!=path.read_bytes():conflicting.add(ident)
            maps[ident]=path
    for review in list(REGION_REVIEWS.values()) + [json.loads(BROTHERS_SPEC.read_text())] + modules + staged:
        for key, record in review.get('map_sources',{}).items():
            ident=int(key);chosen=reference/record['path'];raw=chosen.read_bytes()
            if hashlib.sha256(raw).hexdigest()!=record['sha256']:
                raise ValueError(f'Reviewed map source changed: {chosen}')
            if any(p.read_bytes()[:8]+p.read_bytes()[40:]!=raw[:8]+raw[40:] for p in variants.get(ident,[])):
                raise ValueError(f'Reviewed alias has different map geometry: {ident}')
            maps[ident]=chosen;conflicting.discard(ident)
    ordinary=select_connected_maps(maps,all_portals) | quest_maps
    selected=ordinary | DEV_TRAINING_MAPS | staged_maps
    if selected & conflicting:raise ValueError(f'Conflicting selected map IDs: {sorted(selected & conflicting)}')
    absent=selected-maps.keys()
    if absent:raise ValueError(f'Missing original maps: {absent}')
    # Preserve the existing exploration graph. Extra areas are DEV-only until
    # their entrances, quest gates and progression are restored explicitly.
    portals=ordinary_portals(all_portals, ordinary, quest_maps)
    for portal in portals:
        if portal.get("gate_source")=="genout/wpm_10202_31_13":
            portal["requires_level"]=30
            portal.pop("convenience",None)
    require_seimu_permits(portals)
    disable_conflicting_portals(portals)
    review_scenic_doors(portals)
    unsupported=[dict(p, reason=excluded_reason(maps.get(p['to_map']))) for p in all_portals if p['from_map'] in ordinary and p['to_map'] not in ordinary]
    archive=Archive(source);base=json.loads((output/'samgir.json').read_text()); images={};colors={}; metadata={}; reports={};blocked_portals=[]
    residents=import_residents(archive,reference,root)
    parsed_maps={ident:read_map(maps[ident]) for ident in selected}
    fallback_ids=[]
    if fallback_source:
        missing_values={v for parsed in parsed_maps.values() for layer in parsed[4:6] for v in layer if v>99 and v not in archive.map_ids}
        if missing_values:
            archive=FallbackArchive(archive,Archive(fallback_source),missing_values)
            fallback_ids=archive.logical_ids
    preferred={100:[637,493],200:[570,377],1000:[89,73],2000:[74,56],3000:[84,100],4000:[76,90]}
    for ident in sorted(selected):
        parsed=parsed_maps[ident];data,used,missing=convert(archive,parsed)
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
        kind='village' if ident in TOWNS else 'interior' if ident in REVIEWED_INTERIORS else 'dungeon' if ident in (JYARUGA_SCENIC_MAPS | REVIEWED_REGION_MAPS | quest_maps) else 'training' if ident in DEV_TRAINING_MAPS else 'village' if ident in TOWNS else 'wilderness' if ident in (100,200) else 'interior'
        tones=Counter(m['tone'] for m in data['music_markers'])
        music='world/audio/'+MUSIC[tones.most_common(1)[0][0]] if tones else None
        metadata[str(ident)]=dict(path=f'world/{ident}.map',name=data['name'],width=data['width'],height=data['height'],kind=kind,spawn=spawn,music=music)
        owner=settlement_owner(ident,maps)
        if owner:metadata[str(ident)]['village_id']=owner
        if (ident in DEV_TRAINING_MAPS and ident not in quest_maps) or (ident in staged_maps and ident not in ordinary):metadata[str(ident)]['dev_only']=True
        for p in portals:
            points=[]
            if p['from_map']==ident:points.append(('cell',p['cell']))
            if p['to_map']==ident:points.append(('target',p['target']))
            for field,(x,y) in points:
                if not (0<=x<data['width'] and 0<=y<data['height']):raise ValueError(f'Warp outside map: {p}')
                if data['blocked'][y*data['width']+x]:blocked_portals.append(dict(map_id=ident,field=field,portal=p))
        save_map(root/f'{ident}.map',data);(root/f'{ident}.json').unlink(missing_ok=True)
        reachable=reachable_cells(data,spawn)
        exit_coverage={}
        for p in portals:
            if p['from_map']==ident:
                key=str(p['to_map']);exit_coverage.setdefault(key,dict(reachable=0,unreachable=0));x,y=p['cell']
                exit_coverage[key]['reachable' if reachable[y*data['width']+x] else 'unreachable']+=1
        if ident in TOWNS and not all(v['reachable'] for v in exit_coverage.values()):raise ValueError(f'Village spawn cannot reach exits: {ident} {exit_coverage}')
        reports[str(ident)]=dict(reachable_cells=sum(reachable),exit_coverage=exit_coverage,source=str(maps[ident].relative_to(reference)),sha256=hashlib.sha256(parsed[-1]).hexdigest(),missing_graphics=missing,walkable=data['blocked'].count(0),images=len(used),objects=len(data['objects']))
        print(f'{ident} {data["name"]} {data["width"]}x{data["height"]} missing={len(missing)} spawn={spawn}',flush=True)
    # music_markers keep the original file names; the tracks themselves play from
    # the library tools/import_music.py writes (client/scripts/music_tracks.gd).
    blocked_keys={(p['portal']['from_map'],*p['portal']['cell']) for p in blocked_portals}
    for p in portals:
        if (p['from_map'],*p['cell']) in blocked_keys:p.update(disabled=True,reason='Original warp endpoint collides in available resource revision')
    removed=finalize_reviewed_maps(output,metadata,portals,residents,reports,REVIEWED_REGION_MAPS-quest_maps,reachable_cells,safe_spawn)
    unsupported.extend(dict(p,reason='Original map has no reachable reviewed entry/return component') for p in portals if p['from_map'] not in removed and p['to_map'] in removed)
    portals=[p for p in portals if p['from_map'] not in removed and p['to_map'] not in removed]
    if removed:print(f'Unreachable reviewed maps remain deferred: {sorted(removed)}',flush=True)
    manifest=dict(maps=metadata,residents=residents,portals=portals,teleports=[dict(map_id=i,name=metadata[str(i)]['name'],cell=metadata[str(i)]['spawn']) for i in [1000,2000,3000,4000,100,200]+sorted(TOWNS-VILLAGES)],provenance=dict(server_revision='0c58fb6683a49a178a8ad845a8c296c2cb83bd81',fallback_graphics=dict(source=str(fallback_source) if fallback_ids else None,logical_ids=fallback_ids,bitmap_namespace=1000000000),maps=reports,unsupported_portals=unsupported,blocked_portals=blocked_portals,music='Original map object markers40/41/44/45/46; client system/t_music.cpp play_map_bgm and bgm_tbl. Interiors with no marker preserve preceding track.',limitations=['Original cross-island tunnel imported; its floor10202 quest gate requires original passage permit; runtime must implement gate or label developer bypass.','Imported interiors restore scenery and original doors only; no invented NPC services or quests.','Reviewed settlements and Jyaruga scenery connected by original warps are expanded. Explicit scenic NPC gates are directly open as a developer convenience; quests and NPC services are not restored. Unconnected maps and other special areas remain excluded.', 'Explicit dev_only training maps restore scenery and ordinary source encounters. Giru 300 additionally has reviewed original doors to villages 5000/5100 and their ordinary interiors; other training entrances, quest gates, NPCs, bosses and internal travel links are not restored.']))
    manifest['provenance']['staged_maps'] = sorted(staged_maps - ordinary)
    manifest['provenance']['staged_portals'] = staged_portals
    (root/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(metadata)} maps, {len(portals)} portals, {len(blocked_portals)} blocked endpoints, {len(images)} images')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source');parser.add_argument('--reference',default='references/chenmingbiao-stone-age');parser.add_argument('--output',default='client/assets/legacy');parser.add_argument('--fallback-source');args=parser.parse_args();run(args.source,args.reference,args.output,args.fallback_source)
