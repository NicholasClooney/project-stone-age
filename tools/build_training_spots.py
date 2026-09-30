"""Build safe ordinary training destinations from imported collision/encounter data.

No gated/event mobs, guessed coordinates or replacements for missing artwork.
"""
import argparse
import json
from pathlib import Path

from map_file import load_map


def ordinary_enemies(area, catalog, available):
    if area.get('invalid_weights') or area['probability_max'] <= 0 or area.get('event_now', -1) > 0 or area.get('event_end', -1) > 0:
        return []
    enemies = []
    for choice in area['groups']:
        group = catalog['groups'].get(str(choice['id']))
        if not group or choice['weight'] <= 0:
            continue
        if group['requires_item'] >= 0 or group['excludes_item'] >= 0:
            continue
        if group.get('invalid_weights'):
            return []
        weights = sum(e['weight'] for e in group['enemies'] if e['weight'] > 0)
        if not weights:
            return []
        for entry in group['enemies']:
            if entry['weight'] <= 0:
                continue
            enemy = catalog['enemies'].get(str(entry['id']))
            if not enemy:
                return []
            template = catalog['templates'].get(str(enemy['template_id']))
            if not template or template['sprite'] not in available:
                return []
            if enemy['max_count'] > 0 and enemy['level_min'] > 0:
                enemies.append((enemy, template, choice['weight'] * entry['weight'] / weights))
    return enemies


def renderable_sprites(root):
    """Sprites a battle can show: the encounter art import's report plus the
    battle index (troop_art.gd reads the index, which also holds sprites other
    importers added, such as 金格萨贝鲁's 100330 from the starter pets)."""
    available = set(json.loads((root/'encounters/art-coverage.json').read_text())['available'])
    index = root/'battle/index.json'
    if index.exists():
        data = json.loads(index.read_text())
        available |= {int(k) for k in list(data.get('sprites', {}))+list(data.get('extra_sprites', {}))}
    return available


def effective_area(areas, x, y):
    chosen = None
    for a in areas:
        x1, y1, x2, y2 = a['rect']
        if x1 <= x <= x2 and y1 <= y <= y2 and a['priority'] > (chosen['priority'] if chosen else 0):
            chosen = a
    return chosen


def ground_cells(collision):
    return {(x, y) for x, y, _ in collision['ground']}


def landing(area, areas, collision, forbidden, ground=None):
    width, height = collision['width'], collision['height']
    x1, y1, x2, y2 = area['rect']
    x1, y1, x2, y2 = max(0, x1), max(0, y1), min(width - 1, x2), min(height - 1, y2)
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    # Unblocked cells without a ground picture are the original's black void
    # outside the walls (source tile ids below 100 have no graphic).
    ground = ground if ground is not None else ground_cells(collision)
    # Search actual tiles nearest center; verify the same highest-priority region.
    for radius in range(max(x2-x1, y2-y1) + 1):
        for y in range(max(y1, cy-radius), min(y2, cy+radius)+1):
            for x in range(max(x1, cx-radius), min(x2, cx+radius)+1):
                if max(abs(x-cx), abs(y-cy)) != radius:
                    continue
                if collision['blocked'][y*width+x] or (x, y) not in ground or (x, y) in forbidden:
                    continue
                active = effective_area(areas, x, y)
                if active and active['id'] == area['id']:
                    return [x, y]
    return None


def build(root):
    world = json.loads((root/'world/manifest.json').read_text())
    catalog = json.loads((root/'encounters/catalog.json').read_text())
    available = renderable_sprites(root)
    spots = []
    for key, info in world['maps'].items():
        if int(key) not in (100, 200) and info['kind'] != 'training':
            continue
        collision = load_map(root/info['path'])
        ground = ground_cells(collision)
        areas = [a for a in catalog['areas'] if a['map_id'] == int(key)]
        forbidden = {tuple(p['cell']) for p in world['portals'] if p['from_map'] == int(key)}
        forbidden |= {tuple(n['cell']) for n in world['residents'] if n['map_id'] == int(key)}
        for area in areas:
            enemies = ordinary_enemies(area, catalog, available)
            if not enemies:
                continue
            point = landing(area, areas, collision, forbidden, ground)
            if point is None:
                continue
            weight = sum(w for _, _, w in enemies)
            mean = sum((e['level_min']+e['level_max'])/2*w for e, _, w in enemies)/weight
            spots.append(dict(map_id=int(key), area_id=area['id'], name=info['name'], cell=point,
                              level_min=min(e['level_min'] for e, _, _ in enemies),
                              level_max=max(e['level_max'] for e, _, _ in enemies), mean_level=round(mean, 2),
                              monsters=sorted({t['name'] for _, t, _ in enemies}), dev_only=info.get('dev_only', False)))
    return dict(schema=1, method='Match ordinary enemy mean level; not a measured XP/minute optimum. Source gates and missing art excluded.', spots=spots)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--assets', default='client/assets/legacy')
    p.add_argument('--output', default='client/data/training-spots.json')
    a = p.parse_args()
    output = build(Path(a.assets))
    Path(a.output).write_text(json.dumps(output, ensure_ascii=False, indent=2)+'\n')
    print(f"{len(output['spots'])} verified encounter destinations")
