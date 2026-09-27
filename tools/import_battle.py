"""Extract original first-battle art; run with the same local client as import_legacy.

Original data stays ignored. SAB terrain uses the 2.5 pack's 20x20 layout;
8.5 full-background graphic IDs are deliberately not reused across versions.
"""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path
from PIL import Image
from import_legacy import Archive


def animations(archive, sprite):
    """Read battle actions omitted by the exploration-only decoder's filter."""
    index = (archive.data / 'spradrn_5.bin').read_bytes()
    raw = (archive.data / 'spr_4.bin').read_bytes()
    for offset in range(0, len(index), 12):
        number, at, count = struct.unpack_from('<IIH', index, offset)
        if number == sprite:
            break
    else:
        raise ValueError(f'Missing sprite {sprite}')
    result = {}
    for _ in range(count):
        direction, action, duration, count_frames = struct.unpack_from('<HHII', raw, at)
        at += 12
        if count_frames > 1000 or at + count_frames * 10 > len(raw):
            raise ValueError('Invalid sprite frame count')
        frames = []
        for _ in range(count_frames):
            bitmap, x, y, sound = struct.unpack_from('<IhhH', raw, at)
            at += 10
            frames.append(dict(image=bitmap, x=x, y=y, sound=sound))
        if action in (0, 1, 2, 3, 4, 10):
            result[f'{action}_{direction}'] = dict(duration_ms=duration, frames=frames)
    return result


def run(source, output):
    archive = Archive(source)
    output = Path(output)
    for folder in ('images', 'ui', 'audio'):
        (output / folder).mkdir(parents=True, exist_ok=True)
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    characters = {str(sprite): animations(archive, sprite) for sprite in (100000, 100005, 100010, 100250, 100251, 100252)}
    used = {f['image'] for actions in characters.values() for a in actions.values() for f in a['frames']}
    images = {}
    for bitmap in sorted(used):
        archive.image(bitmap).save(output / 'images' / f'{bitmap}.png')
        images[str(bitmap)] = {k: archive.entries[bitmap][k] for k in ('x', 'y', 'w', 'h')}
    ui = {}
    for number in list(range(25100, 25118)) + list(range(25140, 25144)) + [26014, 26019, 26020, 26040, 26130, 26072, 26061, 26070]:
        bitmap = logical[number]
        archive.image(bitmap).save(output / 'ui' / f'{number}.png')
        ui[str(number)] = dict(bitmap=bitmap, width=archive.entries[bitmap]['w'], height=archive.entries[bitmap]['h'], x=archive.entries[bitmap]['x'], y=archive.entries[bitmap]['y'])
    sab = archive.data / 'battleMap/battle01.sab'
    raw = sab.read_bytes()
    if raw[:4] != b'SAB ' or len(raw) != 804:
        raise ValueError('Expected original 20x20 SAB terrain')
    tiles = struct.unpack('>400H', raw[4:])
    canvas = Image.new('RGBA', (1280, 960))
    for row in range(20):
        for column in range(20):
            e = archive.entries[logical[tiles[row * 20 + column]]]
            canvas.alpha_composite(archive.image(e['id']), (32 * (row + column) + e['x'], 480 + 24 * (row - column) + e['y']))
    # Center crop the fully tiled battle area; no painted or generated pixels.
    background = canvas.crop((328, 246, 888, 666)).resize((800, 600), Image.Resampling.NEAREST)
    if background.getextrema()[3][0] != 255:
        raise ValueError('Battle background contains an uncovered tile or crop edge')
    background.save(output / 'background.png')
    audio = {}
    for key, name in [('bgm', 'bgm/sabgm_b0.wav'), ('menu_open', 'se/sas_02.wav'), ('menu_close', 'se/sas_03.wav'), ('battle_cancel', 'se/sas_17.wav'), ('enemy_attack', 'se/sae_23.wav')]:
        origin = archive.data / name
        shutil.copyfile(origin, output / 'audio' / origin.name)
        audio[key] = 'audio/' + origin.name
    evidence = {
        'client_revision': '1997fc20456dbda36d181b9680ae10bed2e9cdf9',
        'server_revision': '0c58fb6683a49a178a8ad845a8c296c2cb83bd81',
        'ui': 'systeminc/anim_tbl.h CG_BTL_BUTTON_ATTACK_UP25100, GUARD_UP25108, ESCAPE_UP25114, BASE25116; pet command25140..25143; directdraw.cpp3962-3981 pet change26040, item26061, selection26070, skills26130; visually checked against2.5pack',
        'actions': 'systeminc/loadsprbin.h ANIM_ATTACK=0, DAMAGE=1, DEAD=2, STAND=3, WALK=4, GUARD=10',
        'enemy': 'gmsv/data/enemybase.txt first3 rows: 乌力100250, 乌力乌力100251, 乌力斯坦100252; selected classic species, not asserting encounter-table placement',
        'bgm': 'system/battleproc.cpp normal battle play_bgm(5); system/t_music.cpp bgm_tbl[5]=sabgm_b0.wav',
        'background': 'data/battleMap/battle01.sab from local2.5pack; big-endian20x20 graphic IDs; system/battlemap.cpp tile spacing32,-24 and row32,24; selected terrain, not claiming exact server battle-map mapping',
        'background_sha256': hashlib.sha256(raw).hexdigest(),
        'frame_sounds': 'system/pattern.cpp219-224: nonzero SoundNo<10000 plays sound, >=10000 is hit marker. systeminc/sndcnf.h45:73=sae_23.wav (enemy attack SPR); line122:217=sas_17.wav used by BattleButtonOff.',
        'limitations': ['Player attack frames have only0/silence and10000/hit-marker; no invented impact sound.', '2.5 assets and8.5 client references differ; newer full-screen background IDs are incompatible.'],
    }
    manifest = dict(player_id='100000', enemy_id='100250', enemy_name='乌力', characters=characters, images=images, ui=ui, audio=audio, frame_sounds={'73': 'audio/sae_23.wav'}, background=dict(path='background.png', width=800, height=600), provenance=evidence)
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'Imported {len(images)} actor images, {len(ui)} UI images, original SAB terrain and battle BGM')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--output', default='client/assets/legacy/battle')
    args = parser.parse_args()
    run(args.source, args.output)
