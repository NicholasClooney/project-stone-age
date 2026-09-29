"""Import pinned gmsv encounter tables without inventing regional placements.

Keeps conditional records as metadata; ordinary resolver excludes quest/item gates.
Generated resource data stays in ignored original-asset directory.
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path


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
        data['enemies'].setdefault(str(ident),dict(id=ident,name=r[0], tactics=r[1], condition=r[2],template_id=value(r,4),level_min=min(value(r,5),value(r,6)),level_max=max(value(r,5),value(r,6)),max_count=value(r,7),min_count=value(r,8),experience=value(r,10),pet_flag=value(r,13),source_line=line))
    for line,r in rows(root/'enemybase.txt'):
        if len(r)<39:continue
        ident=value(r,6)
        data['templates'].setdefault(str(ident),dict(id=ident,name=r[0],initial=value(r,7),wild_growth=value(r,8),raw_growth=r[8],weights=[value(r,i) for i in range(9,13)],sprite=value(r,36),pet_flag=value(r,37),size=value(r,38),capture_resistance=value(r,14),modai=value(r,13,0),rare=value(r,32),critical=value(r,33),counter=value(r,34),resistances=[value(r,i,0) for i in range(19,25)],elements=[value(r,i) for i in range(15,19)],source_line=line))
    exp_source=(root.parent/'include/enemyexptbl.h').read_text(errors='replace')
    data['experience_table']=[int(x) for x in re.findall(r'\d+',exp_source.split('{',1)[1].split('}',1)[0])]
    data['provenance'] = dict(schema=1, tables={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['encount.txt','group.txt','enemy.txt','enemybase.txt']},
        rules='encount.c ENCOUNT_getEncountAreaArray; enemy.c ENEMY_getEnemyIndexTable/ENEMY_createEnemy; char_walk.c CEP rand()%120',
        limitations=['Quest/event and item-gated groups excluded by ordinary resolver.', 'Rare ENEMY_RandomEnemyArray overrides and special tactics deferred.', 'Original atoi parses wild growth 4.50 as 4; pet training uses separate growth rules.', 'Item drops and special tactics deferred; original enemy XP formula included.'])
    return data

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference',default='references/chenmingbiao-stone-age/gmsv/data')
    p.add_argument('--output',default='client/assets/legacy/encounters/catalog.json')
    a=p.parse_args();data=build(a.reference);out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print({key:len(data[key]) for key in ['areas','groups','enemies','templates']})
