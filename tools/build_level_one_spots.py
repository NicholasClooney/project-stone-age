"""Index genuinely capturable level-one rows at safe ordinary encounter cells."""
import argparse
import json
from pathlib import Path
from build_training_spots import build as build_training, ordinary_enemies


def eligible_pets(area, catalog, available):
    return [(enemy, template) for enemy, template, _ in ordinary_enemies(area, catalog, available)
            if enemy['level_min'] <= 1 <= enemy['level_max'] and enemy.get('pet_flag', 0) != 0]


def build(root):
    training = build_training(root)
    catalog = json.loads((root/'encounters/catalog.json').read_text())
    available = set(json.loads((root/'encounters/art-coverage.json').read_text())['available'])
    areas = {a['id']: a for a in catalog['areas']}
    spots = []
    for point in training['spots']:
        seen = set()
        for enemy, template in eligible_pets(areas[point['area_id']], catalog, available):
            key = (enemy['id'], template['id'])
            if key in seen:
                continue
            seen.add(key)
            spots.append(dict(map_id=point['map_id'], area_id=point['area_id'], cell=point['cell'],
                              map_name=point['name'], name=template['name'], enemy_id=enemy['id'],
                              template_id=template['id'], level_min=enemy['level_min'],
                              level_max=enemy['level_max'], dev_only=point['dev_only']))
    return dict(schema=1, method='Positive ordinary encounter weights, capture flag, actual enemy row includes Lv.1; source-priority safe landing. Encounter chance is not guaranteed.', spots=spots)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--assets', default='client/assets/legacy')
    p.add_argument('--output', default='client/data/level-one-spots.json')
    a = p.parse_args()
    result = build(Path(a.assets))
    Path(a.output).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(f"{len(result['spots'])} verified level-one species locations")
