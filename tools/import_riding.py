"""Import every native rider+pet composite in the server's ridePetTable.

gmsv/char/char_base.c:50 ridePetTable lists, for each classic player
appearance, the pets it can ride and the combined mounted sprite; char.c:3065
and family.c FAMILY_RidePet look up the exact rider+pet pair (first match
wins). Family-leader appearances (1007xx) and the certificate-gated
_NEW_RIDEPETS mounts are not player riders here; see
docs/reverse-engineering/original-riding.md.
"""
import argparse
import json
import re
import shutil
from pathlib import Path
from import_legacy import Archive
from import_battle import animations

# RPlistMode (char_base.c:549): the classic player appearances are 100000..100235.
PLAYER_RIDERS = range(100000, 100240)
ROW = re.compile(r'^\s*\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}', re.M)


def mappings(source):
    """rider:pet -> pair for every uncommented ridePetTable row of a player
    appearance, plus the leader mounts below."""
    text = Path(source).read_bytes().decode('latin1')
    result = {}
    for ride, rider, pet, enemy in ROW.findall(text):
        if int(rider) in PLAYER_RIDERS:
            result.setdefault(f'{rider}:{pet}', dict(sprite=int(ride), rider=int(rider), pet=int(pet), source_enemy_id=int(enemy)))
    for key, pair in leader_mounts(text).items():
        result.setdefault(key, pair)
    return result


# Commented-out family-leader rows (char_base.c:60-61 and every character block
# after it): leader body 100700 + 10k rides 左迪洛斯 100372 and 100705 + 10k rides
# 巴朵兰恩 100373, each with a complete mounted sprite (101008 + 10k, 101009 + 10k).
LEADER_ROW = re.compile(r'^\s*//\s*\{\s*(\d+)\s*,\s*(1007\d\d)\s*,\s*(10037[23])\s*,\s*(\d+)\s*\}', re.M)
LEADER_MOUNTS = {100372, 100373}


def leader_mounts(text):
    """左迪洛斯 and 巴朵兰恩 for every player appearance of the same character.

    The 2.5 data has these two mounts only as family-leader composites; the
    per-appearance certificate composites (_NEW_RIDEPETS) are missing. The game
    has no families, so each character's four colour variants (100000 + 20k +
    0/5/10/15, the block the leader rows sit in) ride with their character's
    leader mounted sprite. `leader_body` records whose art it is."""
    result = {}
    for ride, leader, pet, enemy in LEADER_ROW.findall(text):
        family = (int(leader)-100700)//10
        for colour in range(4):
            rider = 100000+20*family+5*colour
            if rider in PLAYER_RIDERS:
                result.setdefault(f'{rider}:{pet}', dict(sprite=int(ride), rider=rider, pet=int(pet), source_enemy_id=int(enemy), leader_body=int(leader)))
    return result


def species_names(reference, pairs):
    """Pet sprite -> original name of the enemy template each table row cites."""
    from import_encounters import rows, value
    root = Path(reference)
    if not (root/'enemy.txt').exists() or not (root/'enemybase.txt').exists():
        return {}
    templates = {value(r, 6): r[0] for _, r in rows(root/'enemybase.txt') if len(r) >= 39}
    enemies = {}
    for _, r in rows(root/'enemy.txt'):
        if len(r) >= 14:
            enemies.setdefault(value(r, 3), value(r, 4))
    names = {}
    for pair in sorted(pairs.values(), key=lambda p: p['sprite']):
        name = templates.get(enemies.get(pair['source_enemy_id'], -1))
        if name:
            names.setdefault(str(pair['pet']), name)
    return names


def playable(characters):
    """Selectable player appearances, or None when the character import is absent."""
    path = Path(characters)
    if not path.exists():
        return None
    return set(json.loads(path.read_text()).get('characters', {}))


def select(pairs, riders):
    """Split pairs into (kept, unavailable) by playable rider appearance."""
    kept, unavailable = {}, []
    for key, pair in pairs.items():
        if riders is not None and str(pair['rider']) not in riders:
            unavailable.append(dict(pair, reason='rider appearance is not a playable character in this import'))
        else:
            kept[key] = pair
    return kept, unavailable


def run(source, table, output, reference, characters):
    archive = Archive(source)
    output = Path(output)
    (output/'images').mkdir(parents=True, exist_ok=True)
    pairs = mappings(table)
    names = species_names(reference, pairs)
    pairs, unavailable = select(pairs, playable(characters))
    composites = {}
    for key, pair in list(pairs.items()):
        if str(pair['sprite']) in composites:
            continue
        try:
            data = animations(archive, pair['sprite'])
        except ValueError:
            unavailable.append(dict(pair, reason='mounted sprite missing from original pack'))
            del pairs[key]
            continue
        if not all(f'{action}_{direction}' in data and data[f'{action}_{direction}']['frames'] for action in [3, 4] for direction in range(8)):
            unavailable.append(dict(pair, reason='mounted sprite lacks stand/walk in all directions'))
            del pairs[key]
            continue
        composites[str(pair['sprite'])] = data
    used = {f['image'] for c in composites.values() for a in c.values() for f in a['frames']}
    decoded = {}
    invalid = set()
    for ident in sorted(used):
        try:
            decoded[ident] = archive.image(ident)
        except (ValueError, KeyError, IndexError):
            invalid.add(ident)
    broken = {sprite for sprite, actions in composites.items() if any(f['image'] in invalid for a in actions.values() for f in a['frames'])}
    for key, pair in list(pairs.items()):
        if str(pair['sprite']) in broken:
            unavailable.append(dict(pair, reason='invalid bitmap in original pack'))
            del pairs[key]
    for sprite in broken:
        del composites[sprite]
    used = {f['image'] for c in composites.values() for a in c.values() for f in a['frames']}
    images = {}
    for ident in sorted(used):
        decoded[ident].save(output/'images'/f'{ident}.png')
        images[str(ident)] = {k: archive.entries[ident][k] for k in ['x', 'y', 'w', 'h']}
    pets = sorted({p['pet'] for p in pairs.values()})
    manifest = dict(pairs=pairs, characters=composites, images=images, unavailable=unavailable,
                    source='gmsv/char/char_base.c:50 ridePetTable, char.c:3065 exact rider+pet lookup',
                    names={str(pet): names.get(str(pet), str(pet)) for pet in pets})
    add_audio(archive.data, output, manifest)
    (output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    print(f'Imported {len(pairs)} native riding pairs for {len(pets)} pet species, {len(composites)} composites, {len(used)} images; {len(unavailable)} pairs excluded')
    for pair in unavailable:
        print(f"  excluded {pair['rider']}:{pair['pet']} -> {pair['sprite']}: {pair['reason']}")


def add_audio(data, output, manifest):
    (output/'audio').mkdir(parents=True, exist_ok=True)
    sounds = {62: 'sae_12.wav', 63: 'sae_13.wav', 254: 'sad_05.wav'}
    for name in sounds.values():
        shutil.copyfile(data/'se'/name, output/'audio'/name)
    manifest['frame_sounds'] = {str(k): 'audio/'+v for k, v in sounds.items()}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source')
    p.add_argument('--table', default='references/chenmingbiao-stone-age/gmsv/char/char_base.c')
    p.add_argument('--reference', default='references/chenmingbiao-stone-age/gmsv/data', help='server data with enemy.txt / enemybase.txt for pet names')
    p.add_argument('--characters', default='client/assets/legacy/characters/catalog.json', help='imported player characters; riders outside it are skipped')
    p.add_argument('--output', default='client/assets/legacy/riding')
    a = p.parse_args()
    run(a.source, a.table, a.output, a.reference, a.characters)
