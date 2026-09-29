"""Import/validate original battle sprites used by the currently imported world.

No fallback graphic: unavailable sprites are explicitly reported for runtime gating.

Also imports the special pets a developer can grant through GM 调试 (see
docs/reverse-engineering/special-pets.md): no imported map spawns them, so the
world scan alone would skip their sprites. Some exist only in the 8.0 client;
pass it as --extra-source (scripts/setup-original-data.sh --with-8.0 does).
A sprite is read from the first client that has it complete.
"""
import argparse
import json
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


def run(source, root, extra_source=None):
    root=Path(root);archive=Archive(source)
    archives=[archive]+([Archive(extra_source)] if extra_source else [])
    catalog=json.loads((root/'encounters/catalog.json').read_text())
    world=json.loads((root/'world/manifest.json').read_text())
    path=root/'battle/manifest.json';battle=json.loads(path.read_text())
    report={'available':[], 'unavailable':{}}
    for sprite in sorted(required_sprites(catalog,world['maps'])|set(SPECIAL_PETS)):
        try:
            found=None;errors=[]
            for candidate in archives:
                try:
                    actions=complete_actions(candidate,sprite);found=candidate;break
                except (ValueError,KeyError,IndexError) as error:errors.append(str(error))
            if found is None:raise ValueError('; '.join(errors)+('' if extra_source else ' (the 8.0 client may have it: --extra-source)'))
            archive=found
            used={f['image'] for a in actions.values() for f in a['frames']}
            for bitmap in used:
                known=battle['images'].get(str(bitmap))
                if known and known!={k:archive.entries[bitmap][k] for k in ['x','y','w','h']}:
                    raise ValueError(f'bitmap {bitmap} differs from the one already imported')
            for bitmap in used:archive.image(bitmap)
            (root/'battle/images').mkdir(parents=True,exist_ok=True) # pack_frame_sheets.py removes it after packing
            for bitmap in used:
                output=root/'battle/images'/f'{bitmap}.png'
                if not output.exists():archive.image(bitmap).save(output)
                battle['images'][str(bitmap)]={k:archive.entries[bitmap][k] for k in ['x','y','w','h']}
            battle['characters'][str(sprite)]=actions
            report['available'].append(sprite)
        except (ValueError,KeyError,IndexError) as error:
            report['unavailable'][str(sprite)]=str(error)
        for candidate in archives:candidate.cache.clear()
    path.write_text(json.dumps(battle,ensure_ascii=False,indent=2)+'\n')
    (root/'encounters/art-coverage.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source');p.add_argument('--output',default='client/assets/legacy');p.add_argument('--extra-source',help='a later client with sprites the source lacks, for example .tools/legacy/extracted/SA8.0-20260803');a=p.parse_args();run(a.source,a.output,a.extra_source)
