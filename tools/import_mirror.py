"""Incrementally export the original 精灵 art: the spirit equipment's item
graphics and the battle effects (caster, mirror defence, heal and revive).

Effects (gmsv include/anim_tbl.h, battle_magic.h): 100600 MAGIC_EFFECT_USER
on the caster, 100610 SPR_difence (the mirror), 100601-100603 SPR_heal..3 on
a healed member, 100607-100609 SPR_fukkatu1..3 on a revived one, and
100612 SPR_item3 on the medicine user (battle_item.c ITEM_useRessurect). Items
(gmsv data/itemset.txt): 1460 美丽尼亚护身符1 graphic 22018, 1011 哈鲁Lv1铠2
21027, 1112 芙雷雅Lv1服2 and 1113 提欧Lv1服2 21009, 1450 柯雅拉Lv1护身符
22017. No stock rules; no generated artwork."""
import argparse
import json
from pathlib import Path
from import_legacy import Archive
from import_battle import animations

EFFECTS = (100600, 100601, 100602, 100603, 100607, 100608, 100609, 100610, 100612)
ITEMS = [('mirror_charm', 22018, '美丽尼亚护身符1', 1460), ('haru_armor', 21027, '哈鲁Lv1铠2', 1011),
         ('freya_robe', 21009, '芙雷雅Lv1服2', 1112), ('teo_robe', 21009, '提欧Lv1服2', 1113),
         ('koyala_charm', 22017, '柯雅拉Lv1护身符', 1450)]


def run(source, output):
    root = Path(output) / 'mvp'
    (root / 'images').mkdir(parents=True, exist_ok=True)
    archive = Archive(source)
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    items = {}
    for key, number, name, item_id in ITEMS:
        bitmap = logical[number]
        entry = archive.entries[bitmap]
        archive.image(bitmap).save(root / 'images' / f'{key}.png')
        items[key] = dict(name=name, item_id=item_id, graphic=number, bitmap=bitmap, path=f'images/{key}.png', width=entry['w'], height=entry['h'])
    manifest_path = root / 'manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        manifest.setdefault('items', {}).update(items)
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    characters = {str(sprite): animations(archive, sprite) for sprite in EFFECTS}
    images = {}
    (root / 'mirror-effects').mkdir(exist_ok=True)
    for bitmap in sorted({f['image'] for actions in characters.values() for clip in actions.values() for f in clip['frames']}):
        archive.image(bitmap).save(root / 'mirror-effects' / f'{bitmap}.png')
        images[str(bitmap)] = {key: archive.entries[bitmap][key] for key in ('x', 'y', 'w', 'h')}
    result = dict(characters=characters, images=images, image_root='res://assets/legacy/mvp/mirror-effects/',
                  provenance='Original SPR magic100600, heal100601-100603, revive100607-100609, defence100610 and medicine-user SPR_item3=100612 (anim_tbl.h; battle_item.c ITEM_useRessurect); items '
                  + ', '.join(f'{item_id} graphic{number}' for _, number, _, item_id in ITEMS) + '. No generated artwork.')
    (root / 'mirror-effects.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'Spirit items {len(items)} and {len(images)} original effect images exported')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('source')
    p.add_argument('--output', default='client/assets/legacy')
    a = p.parse_args()
    run(a.source, a.output)
