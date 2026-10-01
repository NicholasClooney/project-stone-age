"""Import every native rider+pet composite the server can pick for a player.

gmsv/char/char_base.c:50 ridePetTable lists, for each classic player
appearance, the pets it can ride and the combined mounted sprite; char.c:3065
and family.c FAMILY_RidePet look up the exact rider+pet pair (first match
wins). When no row matches, family.c:2376-2393 (_NEW_RIDEPETS) falls back to
the certificate mounts: RideCodeMode gives the mount's index, RPlistMode the
rider's body row and RideNoList[row][index] the composite (char_base.c:500-560).
Most of those composites (101305 to 101400, 1019xx) exist only in the 8.0
data; pass it with --extra-source. Family-leader appearances (1007xx) are not
player riders here; see docs/reverse-engineering/original-riding.md.
"""
import argparse
import json
import re
import shutil
from pathlib import Path
from import_legacy import Archive, sprite_animations
from sprite_sheets import save_sheets
from split_manifests import split_riding
from import_battle import animations

# RPlistMode (char_base.c:549): the classic player appearances are 100000..100235.
PLAYER_RIDERS = range(100000, 100240)
ROW = re.compile(r'^\s*\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}', re.M)


def mappings(source):
    """rider:pet -> pair in the server's lookup order: every uncommented
    ridePetTable row of a player appearance (family.c:2347), then the
    certificate mounts (family.c:2376), then the leader mounts below for a
    source without the certificate tables."""
    text = Path(source).read_bytes().decode('latin1')
    result = {}
    for ride, rider, pet, enemy in ROW.findall(text):
        if int(rider) in PLAYER_RIDERS:
            result.setdefault(f'{rider}:{pet}', dict(sprite=int(ride), rider=int(rider), pet=int(pet), source_enemy_id=int(enemy)))
    leaders = leader_mounts(text)
    leader_art = {pair['sprite']: pair['leader_body'] for pair in leaders.values()}
    for key, pair in certificate_mounts(text).items():
        if pair['sprite'] in leader_art:
            pair['leader_body'] = leader_art[pair['sprite']]
        result.setdefault(key, pair)
    for key, pair in leaders.items():
        result.setdefault(key, pair)
    return result


# anson1788 familyridefunction.lua:249,252-263 and 8.5 anim_tbl.h:
# RIDE_PET13 in that Lua namespace means gold rex, unlike the C table's
# Holk bit 13. Keep provenance separate; no C learned bit is assigned.
GOLD_REX_BODIES = (103266,103262,103263,103264,103272,103273,
                   103265,103267,103269,103268,103271,103270)
GOLD_REX_SOURCE = 'anson1788 familyridefunction.lua:249,252-263; 8.5 systeminc/anim_tbl.h:2278-2290'

def supplemental_mounts():
    return {f'{100000+20*body+5*colour}:100907': dict(
        sprite=sprite, rider=100000+20*body+5*colour, pet=100907,
        mapping_source=GOLD_REX_SOURCE, source_certificate_namespace='anson1788-lua',
        source_certificate_bit=13)
        for body, sprite in enumerate(GOLD_REX_BODIES) for colour in range(4)}


def block(text, declaration):
    """Body of the last `<declaration>[] = { ... };` initializer. char_base.c
    defines each certificate table twice; the plain variant follows _RIDE_CF,
    and both agree on the 15 defined mounts."""
    starts = [m.end() for m in re.finditer(re.escape(declaration)+r'\s*\[\s*\]\s*=\s*\{', text)]
    if not starts:
        return None
    return text[starts[-1]:text.index('};', starts[-1])]


CODE = re.compile(r'\{\s*(-?\d+)\s*,(?:\s*-?\d+\s*,)?\s*RIDE_PET(\d+)\s*\}\s*,?[ \t]*(?:/\*(.*?)\*/)?')


def ride_codes(text):
    """RideCodeMode (char_base.c:500): [(mount sprite, RIDE_PETn, comment)] in
    table order; RIDEPET_getPETindex (char_base.c:617) returns the position."""
    body = block(text, 'tagRideCodeMode RideCodeMode')
    return [(int(pet), int(bit), (note or '').strip()) for pet, bit, note in CODE.findall(body or '')]


def certificate_mounts(text):
    """Every player appearance x certificate mount with a composite:
    RideNoList[RPlistMode row][RideCodeMode index] (char_base.c:534, 549, 630).
    The row is per character, so a character's four colour variants share it."""
    codes = ride_codes(text)
    lists = block(text, 'tagRideNoList RideNoList')
    bodies = block(text, 'tagRidePetList RPlistMode')
    if not codes or lists is None or bodies is None:
        return {}
    table = [[int(v) for v in re.findall(r'-?\d+', row)] for row in re.findall(r'\{\{([^}]*)\}', lists)]
    rows = {int(char): int(row) for char, row in re.findall(r'\{\s*(\d+)\s*,\s*(\d+)\s*,\s*\d+\s*\}', bodies)}
    result = {}
    for rider in PLAYER_RIDERS:
        row = rows.get(rider, -1)
        if not 0 <= row < len(table):
            continue
        for index, (pet, bit, _) in enumerate(codes):
            if pet < 0 or index >= len(table[row]) or table[row][index] < 0:
                continue
            result.setdefault(f'{rider}:{pet}', dict(sprite=table[row][index], rider=rider, pet=pet, certificate=bit))
    return result


# Commented-out family-leader rows (char_base.c:60-61 and every character block
# after it): leader body 100700 + 10k rides 左迪洛斯 100372 and 100705 + 10k rides
# 巴朵兰恩 100373, each with a complete mounted sprite (101008 + 10k, 101009 + 10k).
LEADER_ROW = re.compile(r'^\s*//\s*\{\s*(\d+)\s*,\s*(1007\d\d)\s*,\s*(10037[23])\s*,\s*(\d+)\s*\}', re.M)
LEADER_MOUNTS = {100372, 100373}


def leader_mounts(text):
    """左迪洛斯 and 巴朵兰恩 for every player appearance of the same character.

    RideNoList (RIDE_PET8/9) gives normal appearances these same leader
    composites, and no client has a normal-outfit version. For a source
    without the certificate tables each character's four colour variants
    (100000 + 20k + 0/5/10/15, the block the leader rows sit in) ride with
    their character's leader sprite. `leader_body` records whose art it is."""
    result = {}
    for ride, leader, pet, enemy in LEADER_ROW.findall(text):
        family = (int(leader)-100700)//10
        for colour in range(4):
            rider = 100000+20*family+5*colour
            if rider in PLAYER_RIDERS:
                result.setdefault(f'{rider}:{pet}', dict(sprite=int(ride), rider=rider, pet=int(pet), source_enemy_id=int(enemy), leader_body=int(leader)))
    return result


def species_names(reference, pairs, notes=None):
    """Pet sprite -> original name of the enemy template each table row cites.

    Certificate mounts cite no enemy: they take the name of an enemy template
    drawn with that sprite, preferring the one the RideCodeMode comment names
    (`notes`: sprite -> comment such as 骑宠扬奇洛斯)."""
    from import_encounters import rows, value
    root = Path(reference)
    if not (root/'enemy.txt').exists() or not (root/'enemybase.txt').exists():
        return {}
    base = [r for _, r in rows(root/'enemybase.txt') if len(r) >= 39]
    templates = {value(r, 6): r[0] for r in base}
    by_sprite = {}
    for r in base:
        by_sprite.setdefault(value(r, 36), []).append(r[0])
    enemies = {}
    for _, r in rows(root/'enemy.txt'):
        if len(r) >= 14:
            enemies.setdefault(value(r, 3), value(r, 4))
    names = {}
    for pair in sorted(pairs.values(), key=lambda p: p['sprite']):
        name = templates.get(enemies.get(pair.get('source_enemy_id', -1), -1))
        if name:
            names.setdefault(str(pair['pet']), name)
    for pair in sorted(pairs.values(), key=lambda p: p['sprite']):
        candidates = [n for n in by_sprite.get(pair['pet'], []) if n]
        if str(pair['pet']) in names or not candidates:
            continue
        note = (notes or {}).get(pair['pet'], '')
        names[str(pair['pet'])] = next((n for n in candidates if n in note), candidates[0])
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


MISSING = 'mounted sprite missing from original pack'
INCOMPLETE = 'mounted sprite lacks required actions in all directions'


def complete(data):
    return all(f'{action}_{direction}' in data and data[f'{action}_{direction}']['frames'] for action in [3, 4] for direction in range(8))


def find_composite(archives, sprite):
    """(archive, actions) from the first archive with a complete composite, or
    (None, reason). The main client comes first, then the extra source for
    what it lacks, so classic pairs keep their 2.5 art."""
    reason = MISSING
    for archive in archives:
        try:
            data = (sprite_animations(archive, sprite, tuple(range(13)))
                    if sprite in GOLD_REX_BODIES else animations(archive, sprite))
        except ValueError:
            continue
        if complete(data) and (sprite not in GOLD_REX_BODIES or all(
                data.get(f'{action}_{direction}', {}).get('frames')
                for action in range(13) for direction in range(8))):
            return archive, data
        reason = INCOMPLETE
    if reason == MISSING and len(archives) == 1:
        reason += ' (the 8.0 data has it: --extra-source)'
    return None, reason


def write_sheets(output, composites, decoded, incremental=False):
    """One sprite sheet (rarely two) per rider+mount composite in output/sheets.

    A composite's hundreds of frames were separate PNGs; one sheet each keeps
    the Godot import, the web packs and their downloads small. Returns the
    manifest's `sheets`: composite -> {files, frames: bitmap -> [sheet, x, y, w, h]}.
    """
    folder = output / 'sheets'
    if not incremental:
        shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True, exist_ok=True)
    result = {}
    for sprite in sorted(composites, key=int):
        used = sorted({f['image'] for a in composites[sprite].values() for f in a['frames']})
        entry = save_sheets({ident: decoded[ident][0] for ident in used}, folder, str(sprite))
        entry['files'] = ['sheets/' + name for name in entry['files']]
        result[str(sprite)] = entry
    return result


def run(source, table, output, reference, characters, extra_source=None, sprites=None):
    archive = Archive(source)
    archives = [archive] + ([Archive(extra_source)] if extra_source else [])
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    # Earlier imports wrote one PNG per frame; sheets replace them.
    if sprites is None:
        shutil.rmtree(output/'images', ignore_errors=True)
    pairs = mappings(table)
    for key, pair in supplemental_mounts().items():
        pairs.setdefault(key, pair)
    notes = {pet: note for pet, _, note in ride_codes(Path(table).read_bytes().decode('gb18030', errors='replace'))}
    names = species_names(reference, pairs, notes)
    pairs, unavailable = select(pairs, playable(characters))
    baseline = {}
    if sprites is not None:
        baseline = json.loads((output/'manifest.json').read_text())
        selected = set(sprites)
        known = {p['sprite'] for p in pairs.values()}
        if selected - known:
            raise ValueError('Unknown selectable composites: ' + ', '.join(map(str, sorted(selected - known))))
        pairs = {key: pair for key, pair in pairs.items() if pair['sprite'] in selected}
        unavailable = [pair for pair in unavailable if pair['sprite'] in selected]
    composites, owner, missing = {}, {}, {}
    for pair in pairs.values():
        sprite = str(pair['sprite'])
        if sprite in composites or sprite in missing:
            continue
        found, data = find_composite(archives, pair['sprite'])
        if found is None:
            missing[sprite] = data
        else:
            composites[sprite], owner[sprite] = data, found
    if sprites is not None and missing:
        raise ValueError(f'Selected composites unavailable; original import preserved: {missing}')
    for key, pair in list(pairs.items()):
        if str(pair['sprite']) in missing:
            unavailable.append(dict(pair, reason=missing[str(pair['sprite'])]))
            del pairs[key]
    decoded = {}
    invalid = set()
    for sprite, actions in composites.items():
        for ident in sorted({f['image'] for a in actions.values() for f in a['frames']}):
            if ident in invalid or (ident in decoded and decoded[ident][1] is owner[sprite]):
                continue
            try:
                image = owner[sprite].image(ident)
            except (ValueError, KeyError, IndexError):
                invalid.add(ident)
                continue
            if ident in decoded and decoded[ident][0].tobytes() != image.tobytes():
                raise ValueError(f'Bitmap {ident} differs between the two clients')
            decoded.setdefault(ident, (image, owner[sprite]))
    broken = {sprite for sprite, actions in composites.items() if any(f['image'] in invalid for a in actions.values() for f in a['frames'])}
    if sprites is not None and broken:
        raise ValueError(f'Selected composites have invalid bitmaps; original import preserved: {sorted(broken)}')
    for key, pair in list(pairs.items()):
        if str(pair['sprite']) in broken:
            unavailable.append(dict(pair, reason='invalid bitmap in original pack'))
            del pairs[key]
    for sprite in broken:
        del composites[sprite]
    used = {f['image'] for c in composites.values() for a in c.values() for f in a['frames']}
    images = {}
    for ident in sorted(used):
        found = decoded[ident][1]
        images[str(ident)] = {k: found.entries[ident][k] for k in ['x', 'y', 'w', 'h']}
    sheets = write_sheets(output, composites, decoded, sprites is not None)
    pets = sorted({p['pet'] for p in pairs.values()})
    manifest = dict(pairs=pairs, characters=composites, images=images, sheets=sheets, unavailable=unavailable,
                    source='gmsv/char/char_base.c:50 ridePetTable, char.c:3065 exact rider+pet lookup',
                    names={str(pet): names.get(str(pet), str(pet)) for pet in pets})
    extra = sorted(int(sprite) for sprite in composites if owner[sprite] is not archive)
    if any('certificate' in p for p in pairs.values()):
        manifest['certificate_source'] = 'gmsv/char/family.c:2376 _NEW_RIDEPETS: RideNoList[RPlistMode row][RideCodeMode index] (char_base.c:500-560); RIDE_PETn learned by item_event.c:3096 ITEM_useLearnRideCode'
    if extra_source:
        manifest['extra_source'] = dict(client=Path(extra_source).name, data=[p.name for p in (archives[1].adrn_path, archives[1].real_path, archives[1].spradrn_path, archives[1].spr_path)], composites=extra)
    if baseline:
        for key in ['pairs','characters','images','sheets','names']:
            manifest[key] = {**baseline.get(key, {}), **manifest[key]}
        manifest['unavailable'] = [p for p in baseline.get('unavailable', []) if p['sprite'] not in selected] + unavailable
        if 'certificate_source' in baseline:
            manifest['certificate_source'] = baseline['certificate_source']
        if extra_source:
            manifest['extra_source']['composites'] = sorted(set(baseline.get('extra_source', {}).get('composites', [])) | set(extra))
    add_audio(archive.data, output, manifest)
    (output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    print(f'Imported {len(pairs)} native riding pairs for {len(pets)} pet species, {len(composites)} composites ({len(extra)} from the extra source), {len(used)} images in {sum(len(s["files"]) for s in sheets.values())} sheets; {len(unavailable)} pairs excluded')
    groups = {}
    for pair in unavailable:
        groups.setdefault(pair['reason'], []).append(pair)
    for reason, group in groups.items():
        if len(group) <= 12:
            for pair in group:
                print(f"  excluded {pair['rider']}:{pair['pet']} -> {pair['sprite']}: {reason}")
        else:
            print(f"  excluded {len(group)} pairs of {len({p['pet'] for p in group})} species: {reason}")


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
    p.add_argument('--extra-source', help='a later client whose data/ has the composites the source lacks, for example .tools/legacy/extracted/SA8.0-20260803')
    p.add_argument('--sprites', type=int, nargs='+', help='refresh only selected composites; requires an existing manifest')
    a = p.parse_args()
    run(a.source, a.table, a.output, a.reference, a.characters, a.extra_source, a.sprites)
    # The game reads riding/index.json and one file per composite (split_manifests.py).
    split_riding(Path(a.output).parent)
