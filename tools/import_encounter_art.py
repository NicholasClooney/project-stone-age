"""Import/validate original battle sprites used by the currently imported world.

No fallback graphic: unavailable sprites are explicitly reported for runtime gating.
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


def run(source, root):
    root=Path(root);archive=Archive(source)
    catalog=json.loads((root/'encounters/catalog.json').read_text())
    world=json.loads((root/'world/manifest.json').read_text())
    path=root/'battle/manifest.json';battle=json.loads(path.read_text())
    report={'available':[], 'unavailable':{}}
    for sprite in sorted(required_sprites(catalog,world['maps'])):
        try:
            actions=animations(archive,sprite)
            for action in [0,1,2,3,4,10]:
                for direction in range(8):
                    if not actions.get(f'{action}_{direction}',{}).get('frames'):
                        raise ValueError(f'missing original action {action}_{direction}')
            used={f['image'] for a in actions.values() for f in a['frames']}
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
        archive.cache.clear()
    path.write_text(json.dumps(battle,ensure_ascii=False,indent=2)+'\n')
    (root/'encounters/art-coverage.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source');p.add_argument('--output',default='client/assets/legacy');a=p.parse_args();run(a.source,a.output)
