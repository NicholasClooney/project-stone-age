"""Precompute every pet species' Lv120 potential for 宠物大全.

Exports the pet templates of the encounter catalog, runs tools/species_potential.c
(full-grade pets, all four growth weights +2, trained to Lv120 with the rules of
client/server/progression.gd) and writes client/data/species_potential.json.
The game only reads that file. See docs/technical/species-potential.md.
"""
import argparse
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIELDS = ['pets', 'mean_sum', 'mean_attack', 'mean_defence', 'mean_speed', 'mean_hp',
          'median', 'top10', 'top1', 'top01', 'max', 'top1_attack', 'top01_attack']


def wild_catch_levels(catalog):
    """Lowest level each template is caught at in ordinary wild encounters.

    Mirrors client/scripts/pet_hunt_rules.gd candidates(): positive weights,
    no event or item gate, valid groups, capturable rows with a real level.
    """
    lowest = {}
    for area in catalog['areas']:
        if area['probability_max'] <= 0 or area.get('invalid_weights') or area.get('event_now', -1) > 0 or area.get('event_end', -1) > 0:
            continue
        for choice in area['groups']:
            group = catalog['groups'].get(str(choice['id']))
            if choice['weight'] <= 0 or not group or group.get('invalid_weights'):
                continue
            if group['requires_item'] >= 0 or group['excludes_item'] >= 0:
                continue
            rows = [catalog['enemies'].get(str(e['id'])) for e in group['enemies']]
            if any(row is None or str(row['template_id']) not in catalog['templates'] for row in rows):
                continue
            for entry, enemy in zip(group['enemies'], rows):
                lo, hi = enemy['level_min'], enemy['level_max']
                if entry['weight'] <= 0 or enemy.get('pet_flag', 0) == 0 or enemy['max_count'] <= 0 or lo < 1 or hi < lo:
                    continue
                tid = enemy['template_id']
                lowest[tid] = min(lowest.get(tid, lo), lo)
    return lowest


def species_rows(catalog):
    lowest = wild_catch_levels(catalog)
    rows = []
    for template in sorted(catalog['templates'].values(), key=lambda t: t['id']):
        if not template.get('pet_flag'):
            continue
        wild = lowest.get(template['id'], 0)
        rows.append((template['id'], int(template['initial']), int(template.get('wild_growth', 4)),
                     *[int(w) for w in template['weights']], wild if wild > 1 else 0))
    return rows, lowest


def parse(output):
    result = {}
    for line in output.splitlines():
        parts = line.split()
        tid, basis, level = int(parts[0]), parts[1], int(parts[2])
        values = {}
        for name, raw in zip(FIELDS, parts[3:]):
            values[name] = round(float(raw), 2) if name.startswith('mean') else int(raw)
        values['level'] = level
        result.setdefault(str(tid), {})[basis] = values
    return result


def build(catalog_path, binary, pets, jobs):
    catalog = json.loads(Path(catalog_path).read_text())
    rows, lowest = species_rows(catalog)
    text = ''.join(' '.join(str(v) for v in row) + '\n' for row in rows)
    output = subprocess.run([str(binary), str(pets), str(jobs)], input=text, capture_output=True, text=True, check=True).stdout
    species = parse(output)
    for tid, entry in species.items():
        entry['wild_level'] = lowest.get(int(tid), 0)
    return dict(schema=1, pets_per_basis=pets,
                method='Full-grade pets (all four growth weights +2) trained to Lv120 with progression.gd rules; '
                       'lv1 is caught at Lv1, wild at the lowest ordinary wild catch level when above 1. '
                       'Fixed seeds; tools/species_potential.c.',
                species=dict(sorted(species.items(), key=lambda item: int(item[0]))))


def dumps(result):
    """One species per line, so a regenerated file diffs by species."""
    head = {k: v for k, v in result.items() if k != 'species'}
    lines = [json.dumps(head, ensure_ascii=False)[:-1] + ',"species":{']
    items = list(result['species'].items())
    for i, (tid, entry) in enumerate(items):
        lines.append(json.dumps(tid) + ':' + json.dumps(entry, separators=(',', ':')) + (',' if i < len(items) - 1 else ''))
    lines.append('}}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--catalog', default=str(ROOT/'client/assets/legacy/encounters/catalog.json'))
    parser.add_argument('--output', default=str(ROOT/'client/data/species_potential.json'))
    parser.add_argument('--binary', default=str(ROOT/'build/species_potential'))
    parser.add_argument('--pets', type=int, default=1000000, help='pets per species and basis')
    parser.add_argument('--jobs', type=int, default=os.cpu_count() or 8)
    args = parser.parse_args()
    binary = Path(args.binary)
    binary.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cc', '-O2', '-o', str(binary), str(ROOT/'tools/species_potential.c')], check=True)
    result = build(args.catalog, binary, args.pets, args.jobs)
    Path(args.output).write_text(dumps(result))
    blue = result['species'].get('92', {}).get('lv1', {})
    print(f"{len(result['species'])} species, {args.pets} pets per basis; template 92 lv1: mean {blue.get('mean_sum')} top1% {blue.get('top1')} top0.1% {blue.get('top01')}")


if __name__ == '__main__':
    main()
