"""Give every imported battle and riding frame its original sound effect.

The original client plays a frame's sound when it is shown (pattern.cpp
219-224): a nonzero SoundNo below 10000 is an SE id, looked up in sndcnf.h's
table (id -> data/se/*.wav); 10000 and up is a hit marker that oft.cpp
play_damage() turns into the hit SE when the strike deals damage
(10000 -> 250, 10001 -> 254, 10002/10003 -> 251, 10004 -> 252, 10007 -> 254,
10005/10006 none; 10100 and up are the same minus 100).

import_battle.py and import_riding.py listed only the few ids their first
sprites used, so pets imported later (for example 红暴龙 100373, whose attack
has only a hit marker, or the swing sounds 1, 3, 56, 60 ...) had no sound.
This step scans the manifests' frames after every other importer, adds each
used SE id and hit SE that the table and the client's data/se have, copies
those files next to the manifest (battle/audio, riding/audio), and records the
ids the table lacks (the original plays nothing for them either).
"""
import argparse
import json
import re
import shutil
from pathlib import Path

TABLE = 'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/systeminc/sndcnf.h'
HIT_SE = {10000: 250, 10001: 254, 10002: 251, 10003: 251, 10004: 252, 10005: None, 10006: None, 10007: 254}


def parse_table(text):
    """sndcnf.h rows `{ id, "data\\se\\name.wav", volume, ...}`; commented rows are skipped."""
    table = {}
    for line in text.splitlines():
        match = re.match(r'\s*\{\s*(\d+)\s*,\s*"data\\\\se\\\\([^"]+\.wav)"', line)
        if match:
            table.setdefault(int(match.group(1)), match.group(2))
    return table


def hit_se(marker):
    if marker >= 10100:
        marker -= 100
    return HIT_SE.get(marker, 250)


def used_sounds(manifest):
    """SE ids the frames play directly, and the hit SEs their markers select."""
    used = set()
    for animations in manifest.get('characters', {}).values():
        for animation in animations.values():
            for frame in animation.get('frames', []):
                sound = int(frame.get('sound', 0))
                if 0 < sound < 10000:
                    used.add(sound)
                elif sound >= 10000 and hit_se(sound) is not None:
                    used.add(hit_se(sound))
    return used


def fill(manifest_path, table, se_folder):
    path = Path(manifest_path)
    text = path.read_text()
    manifest = json.loads(text)
    indented = '\n' in text.strip()
    sounds = dict(manifest.get('frame_sounds', {}))
    (path.parent / 'audio').mkdir(exist_ok=True)
    missing = []
    used = used_sounds(manifest)
    # Pet sprites kept in their own files (battle/pets, import_encounter_art.py).
    for name in manifest.get('extra_sprites', {}).values():
        used |= used_sounds(json.loads((path.parent / name).read_text()))
    for ident in sorted(used):
        name = table.get(ident)
        if name is None or not (se_folder / name).exists():
            missing.append(ident)
            continue
        target = path.parent / 'audio' / name
        if not target.exists():
            shutil.copyfile(se_folder / name, target)
        sounds.setdefault(str(ident), f'audio/{name}')
    manifest['frame_sounds'] = dict(sorted(sounds.items(), key=lambda item: int(item[0])))
    manifest.setdefault('provenance', {})['frame_sounds_table'] = (
        'tools/import_battle_sounds.py: every frame SE id and play_damage hit SE, mapped by '
        'systeminc/sndcnf.h (8.5 client source); ids the table lacks play nothing, as in the original')
    manifest['provenance']['frame_sounds_unmapped'] = missing
    # Keep each manifest's own layout (battle is indented, riding compact).
    if indented:
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    else:
        path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    return len(sounds), missing


def run(source, output, table_path):
    table = parse_table(Path(table_path).read_text(encoding='gb18030', errors='replace'))
    se_folder = Path(source) / 'data/se'
    for name in ('battle/manifest.json', 'riding/manifest.json'):
        manifest = Path(output) / name
        if manifest.exists():
            count, missing = fill(manifest, table, se_folder)
            print(f'{name}: {count} frame sounds' + (f'; not in the original table: {missing}' if missing else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', help='client folder with data/se (the 2.5 client)')
    parser.add_argument('--output', default='client/assets/legacy')
    parser.add_argument('--table', default=TABLE, help='sndcnf.h of the original client source')
    args = parser.parse_args()
    run(args.source, args.output, args.table)
