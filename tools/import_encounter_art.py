"""Import/validate original battle sprites: the imported world's monsters and every pet.

No fallback graphic: unavailable sprites are explicitly reported for runtime gating.

Besides the sprites the imported maps spawn, imports the battle sprite of every
pet template of the encounter catalog, so 宠物大全 can show each species and
GM 调试 can grant the special pets (docs/reverse-engineering/special-pets.md).
That includes the 8.0 pets import_encounters.py adds from the album
(docs/reverse-engineering/pets-8.0.md). About half the pet sprites exist only
in the 8.0 client; pass it as --extra-source (scripts/setup-original-data.sh
--with-8.0 does). A sprite is read from the first client that has it
complete. The manifest and the battle view key bitmaps by number, and the 8.0
client reuses some 2.5 numbers for other pictures: such a bitmap of an 8.0
sprite is renumbered to RENUMBER + its 8.0 number (a number both clients
decode to the same pixels is kept).

The world's sprites and the special pets go into battle/manifest.json as
before. The other pet sprites (about 360, only 宠物大全 and GM grants use them)
each get their own battle/pets/<sprite>.json with the same `characters`,
`images` and (after tools/pack_frame_sheets.py) `sheets` parts, listed under
`extra_sprites` in the manifest; client/scripts/battle_art.gd merges one in on
first use. That keeps the manifest every battle and the web core read at its
old size, and puts each pet's data in its own web pack.

Writes encounters/art-coverage.json: available sprites, the client each came
from, whether it is an extra, and why the rest are unavailable.
"""
import argparse
import json
import shutil
from pathlib import Path
from import_battle import animations
from import_legacy import Archive


def required_sprites(catalog, maps):
    required = set()
    for area in catalog['areas']:
        if str(area['map_id']) not in maps or area['event_now']>0 or area['event_end']>0:
            continue
        for choice in area['groups']:
            group=catalog['groups'].get(str(choice['id']),{})
            if not group or group['requires_item']>=0 or group['excludes_item']>=0:continue
            for choice in group['enemies']:
                enemy=catalog['enemies'].get(str(choice['id']),{})
                template=catalog['templates'].get(str(enemy.get('template_id')), {})
                if template:required.add(template['sprite'])
    return required


def pet_sprites(catalog):
    """The battle sprite of every pet template (enemybase and the 8.0 album pets)."""
    return {t['sprite'] for t in catalog['templates'].values() if t.get('pet_flag')}


# 机暴 帖拉所伊朵, 蓝暴 左迪洛斯, 蓝豹 萨格鲁, 金暴 斑尼迪克, 机豹 艾迪希洛 (8.0 only),
# 年兽 x4, 黑乌力王 (8.0 only), 黑乌力. 红暴 100373 already spawns on map 500.
SPECIAL_PETS = [100374, 100372, 100873, 100907, 101423, 101152, 101153, 101154, 101155, 101871, 100388]


def complete_actions(archive, sprite):
    actions=animations(archive,sprite)
    for action in [0,1,2,3,4,10]:
        for direction in range(8):
            if not actions.get(f'{action}_{direction}',{}).get('frames'):
                raise ValueError(f'missing original action {action}_{direction}')
    return actions


RENUMBER = 1000000000


def renumbering(primary, other, bitmaps):
    """Bitmap -> manifest number for a sprite read from a later client: its own
    number unless the primary client has another picture under it."""
    result = {}
    for bitmap in bitmaps:
        same = False
        if bitmap in primary.entries:
            try:
                same = primary.image(bitmap).tobytes() == other.image(bitmap).tobytes()
            except (ValueError, KeyError, IndexError):
                same = False
        result[bitmap] = bitmap if same or bitmap not in primary.entries else RENUMBER + bitmap
    return result


def load_sprite(archives, sprite, extra_source):
    """(actions renumbered for the manifest, {manifest number: (archive, bitmap)}, client index)."""
    found=None;errors=[]
    for candidate in archives:
        try:
            actions=complete_actions(candidate,sprite);found=candidate;break
        except (ValueError,KeyError,IndexError) as error:errors.append(str(error))
    if found is None:raise ValueError('; '.join(errors)+('' if extra_source else ' (the 8.0 client may have it: --extra-source)'))
    used={f['image'] for a in actions.values() for f in a['frames']}
    number=renumbering(archives[0],found,used) if found is not archives[0] else {b:b for b in used}
    for bitmap in used:found.image(bitmap)
    for action in actions.values():
        for frame in action['frames']:frame['image']=number[frame['image']]
    return actions,{number[b]:(found,b) for b in used},archives.index(found)


def run(source, root, extra_source=None, pets=True):
    root=Path(root);archive=Archive(source)
    archives=[archive]+([Archive(extra_source)] if extra_source else [])
    names=['2.5']+(['8.0'] if extra_source else [])
    catalog=json.loads((root/'encounters/catalog.json').read_text())
    world=json.loads((root/'world/manifest.json').read_text())
    path=root/'battle/manifest.json';battle=json.loads(path.read_text())
    base=required_sprites(catalog,world['maps'])|set(SPECIAL_PETS)
    previous=set(battle.get('extra_sprites',{}))
    # Sprites another importer put in the manifest (starters, the player) stay there.
    others={int(k) for k in battle['characters']}-previous
    extras=(pet_sprites(catalog)-base-others) if pets else set()
    report={'available':[], 'unavailable':{}, 'sources':{}, 'extra':[]}
    images=root/'battle/images';images.mkdir(parents=True,exist_ok=True) # pack_frame_sheets.py removes it after packing
    folder=root/'battle/pets'
    if folder.exists():shutil.rmtree(folder)
    battle['extra_sprites']={}
    for sprite in sorted(base|extras):
        try:
            actions,bitmaps,client=load_sprite(archives,sprite,extra_source)
            geometry={str(n):{k:a.entries[b][k] for k in ['x','y','w','h']} for n,(a,b) in bitmaps.items()}
            for key,value in geometry.items():
                known=battle['images'].get(key)
                if known and known!=value:raise ValueError(f'bitmap {key} differs from the one already imported')
            for n,(a,b) in bitmaps.items():
                output=images/f'{n}.png'
                if not output.exists():a.image(b).save(output)
            if sprite in extras:
                folder.mkdir(exist_ok=True)
                (folder/f'{sprite}.json').write_text(json.dumps({'characters':{str(sprite):actions},'images':geometry},ensure_ascii=False,separators=(',',':')))
                battle['extra_sprites'][str(sprite)]=f'pets/{sprite}.json'
                battle['characters'].pop(str(sprite),None);battle.get('sheets',{}).pop(str(sprite),None)
                report['extra'].append(sprite)
            else:
                battle['images'].update(geometry)
                battle['characters'][str(sprite)]=actions
            report['available'].append(sprite)
            report['sources'][str(sprite)]=names[client]
        except (ValueError,KeyError,IndexError) as error:
            report['unavailable'][str(sprite)]=str(error)
        for candidate in archives:candidate.cache.clear()
    battle.setdefault('provenance',{})['encounter_art']=dict(
        clients=[Path(a.source).name for a in archives],
        sprites='world spawns and SPECIAL_PETS in this manifest; every other pet template of encounters/catalog.json in pets/<sprite>.json (extra_sprites)' if pets else 'world spawns and SPECIAL_PETS',
        rule=f'first client with actions 0-4 and 10 in all eight directions; an 8.0 bitmap whose number 2.5 uses for another picture becomes {RENUMBER} + its number',
        from_extra_source=sum(1 for v in report['sources'].values() if v!='2.5'))
    report['counts']=dict(available=len(report['available']),unavailable=len(report['unavailable']),extra=len(report['extra']),
        by_source={n:sum(1 for v in report['sources'].values() if v==n) for n in names})
    path.write_text(json.dumps(battle,ensure_ascii=False,indent=2)+'\n')
    (root/'encounters/art-coverage.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['counts'],ensure_ascii=False),json.dumps(report['unavailable'],ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter);p.add_argument('source');p.add_argument('--output',default='client/assets/legacy');p.add_argument('--extra-source',help='a later client with sprites the source lacks, for example .tools/legacy/extracted/SA8.0-20260803');p.add_argument('--no-pets',action='store_true',help='only the world spawns and the special pets, not every pet template');a=p.parse_args();run(a.source,a.output,a.extra_source,not a.no_pets)
