"""Incrementally export original mirror accessory and battle effects; no stock rules."""
import argparse
import json
from pathlib import Path
from import_legacy import Archive
from import_battle import animations


def run(source, output):
    root=Path(output)/'mvp'
    (root/'images').mkdir(parents=True,exist_ok=True)
    archive=Archive(source)
    logical={e['map_id']:e['id'] for e in archive.entries.values() if e['map_id']}
    bitmap=logical[22018]
    archive.image(bitmap).save(root/'images/mirror_charm.png')
    characters={str(sprite):animations(archive,sprite) for sprite in (100600,100610)}
    images={}
    (root/'mirror-effects').mkdir(exist_ok=True)
    for bitmap in sorted({f['image'] for actions in characters.values() for clip in actions.values() for f in clip['frames']}):
        archive.image(bitmap).save(root/'mirror-effects'/f'{bitmap}.png')
        images[str(bitmap)]={key:archive.entries[bitmap][key] for key in ('x','y','w','h')}
    result=dict(characters=characters,images=images,image_root='res://assets/legacy/mvp/mirror-effects/',provenance='Original SPR magic100600 and defence100610; item1460 graphic22018. No generated artwork.')
    (root/'mirror-effects.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(f'Mirror accessory and {len(images)} original effect images exported')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('--output',default='client/assets/legacy');a=p.parse_args();run(a.source,a.output)
