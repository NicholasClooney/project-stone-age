"""Group the pet templates into families (系) for 宠物大全.

The original client's pet album (宠物相簿) lists pets in pages of eight,
one family per page: the four base forms and four later variants
(references/anson1788-stoneage/.../systeminc/petName.h, PetAlbumTbl in
system/menu.cpp; album number // 8 is the page). A template joins the page of
its album name; a template whose name is not in the album joins the family of
another template with the same battle sprite; the rest go to 其他.
Writes client/data/pet_families.json. See docs/development/pet-encyclopedia.md.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALBUM = ROOT/'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/systeminc/petName.h'
# Names players use for a few well-known families; the rest are named after
# the page's first pet.
NAMES = {0: '乌力系', 1: '布伊系', 2: '加美系', 5: '龟系', 9: '人龙系', 15: '虎系', 24: '暴龙系', 28: '年兽系'}
OTHER = 999


def album(path):
    rows = re.findall(r'\{\s*(\d+),\s*"([^"]*)"[^,]*,\s*(\d+)\s*\}', Path(path).read_text(encoding='utf-8-sig'))
    numbers = {}
    for number, name, _face in rows:
        name = name.strip()
        if name and name not in numbers:
            numbers[name] = int(number)
    return numbers


def build(catalog, numbers):
    pets = [t for t in catalog['templates'].values() if t.get('pet_flag')]
    placed = {}
    for template in pets:
        number = numbers.get(template['name'])
        if number is not None:
            placed[template['id']] = (number // 8, number)
    by_sprite = {}
    for template in sorted(pets, key=lambda t: t['id']):
        if template['id'] in placed:
            by_sprite.setdefault(template['sprite'], placed[template['id']])
    for template in pets:
        if template['id'] not in placed:
            page, number = by_sprite.get(template['sprite'], (OTHER, 1 << 20))
            placed[template['id']] = (page, number + 0.5)
    families = {}
    for template in sorted(pets, key=lambda t: (placed[t['id']][1], t['id'])):
        families.setdefault(placed[template['id']][0], []).append(template)
    result = []
    for page in sorted(families):
        members = families[page]
        # Named after the page's first pet, skipping numbered names (变色龙2).
        first = next((t['name'] for t in members if not re.search(r'\d', t['name'])), members[0]['name'])
        name = '其他' if page == OTHER else NAMES.get(page, first + '系')
        result.append(dict(id=page, name=name, templates=[t['id'] for t in members]))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--catalog', default=str(ROOT/'client/assets/legacy/encounters/catalog.json'))
    parser.add_argument('--album', default=str(ALBUM))
    parser.add_argument('--output', default=str(ROOT/'client/data/pet_families.json'))
    args = parser.parse_args()
    catalog = json.loads(Path(args.catalog).read_text())
    families = build(catalog, album(args.album))
    lines = ['{"schema":1,"source":"8.5 client pet album (petName.h), one page of eight per family; unmatched names by battle sprite; rest 其他","families":[']
    for i, family in enumerate(families):
        lines.append(json.dumps(family, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(families) - 1 else ''))
    lines.append(']}')
    Path(args.output).write_text('\n'.join(lines) + '\n')
    print(f"{len(families)} families, {sum(len(f['templates']) for f in families)} templates")


if __name__ == '__main__':
    main()
