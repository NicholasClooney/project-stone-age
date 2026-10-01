"""Import pinned gmsv encounter tables without inventing regional placements.

Keeps conditional records as metadata; server resolves inventory gates.
Generated resource data stays in ignored original-asset directory.

Also adds the later pets the reference server has no template for: the 8.5
client's pet album names them and the 8.0 client has their battle sprites
(docs/reverse-engineering/pets-8.0.json, see pets-8.0.md). They get template
ids 10000 + album number, `source` '8.0' and `stats_known` false: no original
stats exist, so they carry none. No encounter group names them, so they never
spawn. The enemybase templates stay as they are.

Then it merges client/data/rare-encounters.json: rare Lv1 pets in higher-level
areas, the original's own pattern (docs/reverse-engineering/
rare-level-one-encounters.md). This is the one place those additions enter the
catalog; the server rolls, the fast hunt helper, 宠物大全, the spot builders and
the Lv120 predictions all read the result. Added groups and cloned enemies
carry `rare` / `clone_of` so nothing mistakes them for original rows.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

ALBUM_PETS = Path(__file__).resolve().parent.parent/'docs/reverse-engineering/pets-8.0.json'
ALBUM = Path('references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/systeminc/petname.h')
ALBUM_BASE = 10000
RARE = Path(__file__).resolve().parent.parent/'client/data/rare-encounters.json'
ORIGINS = ('original_area', 'added')


def atoi(value):
    match = re.match(r'\s*([+-]?\d+)', value)
    return int(match[1]) if match else 0


def rows(path):
    for line, row in enumerate(csv.reader(path.read_bytes().decode('gb18030', errors='replace').splitlines()), 1):
        if row and row[0].strip() and not row[0].lstrip().startswith('#'):
            yield line, row


def value(row, index, default=-1):
    return atoi(row[index]) if index < len(row) and row[index].strip() else default


def choices(row, ids, weights):
    return [{'id': value(row, ids+i), 'weight': value(row, weights+i, 0)}
            for i in range(10) if value(row, ids+i) >= 0 and value(row, weights+i, -1) >= 0]


def malformed_weights(row, ids, weights):
    return any(value(row, ids+i)>=0 and value(row, weights+i)<0 for i in range(10))


def drop_slots(row):
    """ENEMY_ITEM1..10 (14..23), ITEMPROB1..10 (24..33), _FIX_ITEMPROB."""
    return [dict(slot=i, item_id=value(row,14+i), probability=value(row,24+i,0), denominator=1000)
            for i in range(10) if value(row,14+i)>0]

def wait_only(tactics):
    # Conservative subset: never interpret an unrecognised tactic as idle.
    return bool(re.fullmatch(r'at:0;[^|]*\|gu:0\|es:0\|wa:[1-9]\d*;[0;]*', tactics))


def album_names(path):
    """Album number -> name from petName.h, commented rows skipped."""
    names = {}
    for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
        match = re.match(r'\{\s*(\d+),\s*"([^"]*)"', line.strip())
        if match:
            names.setdefault(int(match[1]), match[2].strip())
    return names


def add_album_pets(data, path=ALBUM_PETS, album=ALBUM):
    """Adds the 8.0 pets of pets-8.0.json as stat-less templates."""
    path = Path(path)
    pets = json.loads(path.read_text())['pets']
    names = album_names(album) if Path(album).exists() else None
    known = {t['name'] for t in data['templates'].values()}
    for pet in pets:
        ident = ALBUM_BASE+pet['album']
        if names is not None and names.get(pet['album']) != pet['name']:
            raise ValueError(f"album {pet['album']} is {names.get(pet['album'])!r} in petName.h, not {pet['name']!r}")
        if str(ident) in data['templates'] or pet['name'] in known:
            raise ValueError(f"{pet['name']} ({ident}) already has a template")
        data['templates'][str(ident)] = dict(id=ident, name=pet['name'], sprite=pet['sprite'], pet_flag=1, source='8.0', stats_known=False, album=pet['album'], face=pet['face'])
    data['provenance']['album_pets'] = dict(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), count=len(pets),
        names='8.5 client systeminc/petName.h PetAlbumTbl' + ('' if names is not None else ' (not checked: reference missing)'),
        sprites='8.0 client data, paired by the album face graphic', stats='none known')
    return data


def _ordinary_enemy_ids(data, area):
    """Enemy ids of the area's ordinary (not item-gated) groups."""
    ids = set()
    for choice in area['groups']:
        group = data['groups'].get(str(choice['id']))
        if group and choice['weight'] > 0 and group['requires_item'] < 0 and group['excludes_item'] < 0:
            ids |= {e['id'] for e in group['enemies'] if e['weight'] > 0}
    return ids


def add_rare_encounters(data, path=RARE):
    """Merges rare-encounters.json (see the module docstring) into data.

    areas: multiply one area's group weights by `scale` (ratios unchanged).
    clones: copy an enemy row at Lv1, capturable, at most one per troop.
    encounters: a new group {Lv1 enemy 1, companion 1} with area weight
    `weight`. The companion must already be in an ordinary group of that area.
    With `alone_group_id` a second group holds the Lv1 enemy alone (as many
    copies as its row's max_count allows, like the original's single Lv1
    groups), also with area weight `weight`, so a hunt that only enters
    troops of Lv1 enemies finds the pet too. Its `rare` has `alone: true`.
    """
    path = Path(path)
    spec = json.loads(path.read_text())

    def area_of(map_id, area_id):
        found = [a for a in data['areas'] if a['map_id'] == map_id and a['id'] == area_id]
        if len(found) != 1:
            raise ValueError(f'area {area_id} on map {map_id}: {len(found)} matches')
        return found[0]

    for item in spec.get('areas', []):
        area = area_of(item['map_id'], item['area_id'])
        if int(item['scale']) < 1 or 'weight_scale' in area:
            raise ValueError(f"bad or repeated scale for area {item['area_id']}")
        for choice in area['groups']:
            choice['weight'] *= int(item['scale'])
        area['weight_scale'] = int(item['scale'])
    for item in spec.get('clones', []):
        source = data['enemies'].get(str(item['from']))
        if source is None or str(item['id']) in data['enemies'] or source['template_id'] != item['template_id']:
            raise ValueError(f"clone {item['id']} of enemy {item['from']}: missing source, taken id or wrong template")
        data['enemies'][str(item['id'])] = dict(source, id=item['id'], name=f"Lv1{data['templates'][str(source['template_id'])]['name']}（补）",
            level_min=1, level_max=1, max_count=1, min_count=1, pet_flag=1, clone_of=item['from'], source_line=-1)
    for item in spec['encounters']:
        area = area_of(item['map_id'], item['area_id'])
        enemy = data['enemies'].get(str(item['enemy_id']))
        if enemy is None or enemy['template_id'] != item['template_id'] or (enemy['level_min'], enemy['level_max']) != (1, 1) or enemy['pet_flag'] == 0:
            raise ValueError(f"group {item['group_id']}: enemy {item['enemy_id']} is not a capturable Lv1 {item['name']}")
        if data['templates'][str(item['template_id'])]['name'] != item['name']:
            raise ValueError(f"group {item['group_id']}: template {item['template_id']} is not {item['name']}")
        if item['origin'] not in ORIGINS or str(item['group_id']) in data['groups']:
            raise ValueError(f"group {item['group_id']}: bad origin or taken id")
        members = [dict(id=item['enemy_id'], weight=1)]
        if item.get('companion_id') is not None:
            if item['companion_id'] not in _ordinary_enemy_ids(data, area):
                raise ValueError(f"group {item['group_id']}: companion {item['companion_id']} is not already in area {item['area_id']}")
            members.append(dict(id=item['companion_id'], weight=1))
        data['groups'][str(item['group_id'])] = dict(id=item['group_id'], name=f"rare_lv1_{item['template_id']}", requires_item=-1, excludes_item=-1,
            enemies=members, invalid_weights=False, source_line=-1,
            rare=dict(origin=item['origin'], template_id=item['template_id'], enemy_id=item['enemy_id'], reason=item['reason']))
        area['groups'].append(dict(id=item['group_id'], weight=item['weight']))
        alone = item.get('alone_group_id')
        if alone is not None:
            if item.get('companion_id') is None or str(alone) in data['groups']:
                raise ValueError(f"group {alone}: alone group of {item['group_id']} needs a companion group and a free id")
            data['groups'][str(alone)] = dict(id=alone, name=f"rare_lv1_{item['template_id']}_alone", requires_item=-1, excludes_item=-1,
                enemies=[dict(id=item['enemy_id'], weight=1)], invalid_weights=False, source_line=-1,
                rare=dict(origin=item['origin'], template_id=item['template_id'], enemy_id=item['enemy_id'], alone=True,
                    reason=f"只含 Lv1 {item['name']} 的补充组（非原版）：同原版加鲁卡、吉鲁岛、沙姆岛的单独 Lv1 组；同区另有它与高等级同伴的组 {item['group_id']}"))
            area['groups'].append(dict(id=alone, weight=item['weight']))
    data['provenance']['rare_encounters'] = dict(file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        encounters=len(spec['encounters']), alone=sum(1 for item in spec['encounters'] if item.get('alone_group_id') is not None), clones=len(spec.get('clones', [])), scaled_areas=len(spec.get('areas', [])),
        rule='docs/reverse-engineering/rare-level-one-encounters.md; not original rows')
    return data


def build(root):
    root = Path(root)
    data = dict(areas=[], groups={}, enemies={}, templates={}, provenance={})
    for line, r in rows(root/'encount.txt'):
        if len(r)<10: continue
        x1,y1,x2,y2 = [value(r,i,0) for i in range(2,6)]
        data['areas'].append(dict(id=value(r,0), map_id=value(r,1),
            rect=[min(x1,x2),min(y1,y2),max(x1,x2),max(y1,y2)],
            probability_min=min(value(r,6),value(r,7)), probability_max=max(value(r,6),value(r,7)),
            max_enemies=value(r,8), priority=value(r,9), groups=choices(r,10,20), invalid_weights=malformed_weights(r,10,20),
            event_now=value(r,30), event_end=value(r,31), event_group=value(r,32), source_line=line))
    for line,r in rows(root/'group.txt'):
        if len(r)<14: continue
        ident=value(r,1)
        data['groups'].setdefault(str(ident),dict(id=ident,name=r[0],requires_item=value(r,2), excludes_item=value(r,3),enemies=choices(r,4,14),invalid_weights=malformed_weights(r,4,14),source_line=line))
    for line,r in rows(root/'enemy.txt'):
        if len(r)<14:continue
        ident=value(r,3)
        data['enemies'].setdefault(str(ident),dict(id=ident,name=r[0], tactics=r[1], condition=r[2],template_id=value(r,4),level_min=min(value(r,5),value(r,6)),level_max=max(value(r,5),value(r,6)),max_count=value(r,7),min_count=value(r,8),experience=value(r,10),pet_flag=value(r,13),drops=drop_slots(r),wait_only=wait_only(r[1]),source_line=line))
    for line,r in rows(root/'enemybase.txt'):
        if len(r)<39:continue
        ident=value(r,6)
        data['templates'].setdefault(str(ident),dict(id=ident,name=r[0],initial=value(r,7),wild_growth=value(r,8),raw_growth=r[8],weights=[value(r,i) for i in range(9,13)],sprite=value(r,36),pet_flag=value(r,37),size=value(r,38),capture_resistance=value(r,14),modai=value(r,13,0),rare=value(r,32),critical=value(r,33),counter=value(r,34),resistances=[value(r,i,0) for i in range(19,25)],elements=[value(r,i) for i in range(15,19)],source_line=line))
    exp_source=(root.parent/'include/enemyexptbl.h').read_text(errors='replace')
    data['experience_table']=[int(x) for x in re.findall(r'\d+',exp_source.split('{',1)[1].split('}',1)[0])]
    data['provenance'] = dict(schema=1, tables={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['encount.txt','group.txt','enemy.txt','enemybase.txt']},
        rules='encount.c ENCOUNT_getEncountAreaArray; enemy.c ENEMY_getEnemyIndexTable/ENEMY_createEnemy; char_walk.c CEP rand()%120',
        limitations=['Quest/event conditions remain deferred; item gates use authoritative inventory.', 'Rare ENEMY_RandomEnemyArray overrides and special tactics deferred.', 'Original atoi parses wild growth 4.50 as 4; pet training uses separate growth rules.', 'Drop tables retain ITEM1..10/ITEMPROB1..10 and _FIX_ITEMPROB RAND(0,999); runtime activates only audited wood enemy 563. Only wait-only tactics implemented; original enemy XP formula included.'])
    return data

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference',default='references/chenmingbiao-stone-age/gmsv/data')
    p.add_argument('--output',default='client/assets/legacy/encounters/catalog.json')
    p.add_argument('--album-pets',default=str(ALBUM_PETS),help='the 8.0 pets without an enemybase template; "" to leave them out')
    p.add_argument('--rare',default=str(RARE),help='rare Lv1 encounters to merge; "" to leave them out')
    a=p.parse_args();data=build(a.reference);out=Path(a.output)
    if a.album_pets:add_album_pets(data,a.album_pets)
    if a.rare:add_rare_encounters(data,a.rare)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print({key:len(data[key]) for key in ['areas','groups','enemies','templates']})
