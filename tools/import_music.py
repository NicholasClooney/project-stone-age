"""Import every original background track for the in-game radio (电台).

Source: the client's data/bgm/sabgm_*.wav. The 8.0 client has 26 tracks, the
2.5 client 24 (no t11/t12, and an older t9); pass the 8.0 folder when it is
extracted, see scripts/setup-original-data.sh --with-8.0.

Titles come from bgm_tbl in the 8.5 client source (system/t_music.cpp,
references/anson1788-stoneage). Its comments are GBK text that was decoded
as Big5 and saved again; encoding them as Big5 and decoding as GBK recovers
伊甸大陆, 水城 and the rest. Comments lost entirely (the Japanese ones for the
first twelve entries) are named after where the original plays the track
(play_bgm callers, map object markers 40-46) instead.

Tracks are encoded to Ogg Vorbis (tools/music_codec.py: about q6, cut at the
original loop end, with the loop start recorded as `loop_start` seconds) into
client/assets/legacy/music/ with manifest.json; without an encoder the WAV is
copied instead. This folder is the game's one music library: the map, battle
and radio music all play from it (scripts/music_tracks.gd), and the web
build streams it rather than decoding it (docs/technical/web-client.md).
plan_web_packs.py gives each track its own web pack, so a browser downloads a
track only when it plays; the battle music travels in the core pack.
The original WAVs stay in the extracted client for a lossless option later.
"""
import argparse
import json
import shutil
from pathlib import Path

import music_codec

# id: (title, kind, where the original plays it). Order is the radio's order.
TRACKS = {
    'sabgm_t0': ('萨姆吉尔村', 'town', 'Villages: map marker 40 (Samgir, Marinas, Jaja, Karutana).'),
    'sabgm_t1': ('村落', 'town', 'Villages and towns: map marker 41 (Kao, Hotel, Katan, Dana and others).'),
    'sabgm_f0': ('原野', 'field', 'Overworld: map marker 45 (Sainasu, Giru, Shamu islands).'),
    'sabgm_f1': ('加鲁卡原野', 'field', 'Overworld: map marker 46 (Garuka).'),
    'sabgm_d0': ('洞窟', 'dungeon', 'bgm_tbl entry 7.'),
    'sabgm_d1': ('深层洞窟', 'dungeon', 'bgm_tbl entry 8.'),
    'sabgm_d2': ('地下通路', 'dungeon', 'Dungeons: map marker 44 (undersea passage, Five Brothers fort).'),
    'sabgm_b0': ('战斗', 'battle', 'bgm_tbl entry 5, ordinary battles (battleproc.cpp).'),
    'sabgm_b1': ('头目战斗', 'battle', 'bgm_tbl entry 6, boss battles (battleproc.cpp).'),
    'sabgm_s1': ('登录', 'theme', 'bgm_tbl entries 1-2, the login screen (login.cpp).'),
    'sabgm_f2': ('伊甸大陆', 'field', 'bgm_tbl entry 15 (伊甸大陆).'),
    'sabgm_t2': ('伊甸园', 'town', 'bgm_tbl entry 16 (伊甸园).'),
    'sabgm_t3': ('地城', 'town', 'bgm_tbl entry 17 (地城).'),
    'sabgm_t4': ('水城', 'town', 'bgm_tbl entry 18 (水城).'),
    'sabgm_t5': ('火城', 'town', 'bgm_tbl entry 19 (火城).'),
    'sabgm_t6': ('风城', 'town', 'bgm_tbl entry 20 (风城).'),
    'sabgm_t7': ('赌场', 'town', 'bgm_tbl entry 21 (赌埸).'),
    'sabgm_b3': ('新的一般战斗', 'battle', 'bgm_tbl entry 12 (新的一般战斗).'),
    'sabgm_b2': ('新的头目战斗', 'battle', 'bgm_tbl entry 13 (新的boss战斗).'),
    'sabgm_b4': ('最终头目战斗', 'battle', 'bgm_tbl entry 14 (新的最后boss战斗), floor 8519.'),
    'sabgm_t8': ('海底洞窟', 'dungeon', 'bgm_tbl entry 22 (海底洞窟).'),
    'sabgm_t9': ('海底原野', 'field', 'bgm_tbl entry 23 (海底原).'),
    'sabgm_t10': ('海底战斗', 'battle', 'bgm_tbl entry 24 (海底战斗).'),
    'sabgm_s0': ('胜利', 'jingle', 'bgm_tbl entry 0, after a won battle (oft.cpp).'),
    'sabgm_t11': ('短曲一', 'jingle', 'bgm_tbl entry 25, untitled 8.0 addition.'),
    'sabgm_t12': ('短曲二', 'jingle', 'bgm_tbl entry 26, untitled 8.0 addition.'),
}


def transcode(wav: Path, folder: Path) -> tuple:
    """(file written, music_codec.layout): Ogg Vorbis, or the original WAV."""
    ogg = folder / f'{wav.stem}.ogg'
    try:
        info = music_codec.encode(wav, ogg)
        (folder / wav.name).unlink(missing_ok=True)
        return ogg, info
    except RuntimeError as error:
        print(f'{error}; keeping the WAV')
    ogg.unlink(missing_ok=True)
    target = folder / wav.name
    shutil.copyfile(wav, target)
    return target, music_codec.layout(wav)


def run(source, output):
    bgm = Path(source) / 'data/bgm'
    if not bgm.is_dir():
        raise SystemExit(f'No data/bgm in {source}')
    folder = Path(output) / 'music'
    folder.mkdir(parents=True, exist_ok=True)
    tracks = []
    for ident, (title, kind, note) in TRACKS.items():
        wav = bgm / f'{ident}.wav'
        if not wav.exists():
            continue
        file, info = transcode(wav, folder)
        # seconds: the stream's length (cut at the loop end); loop_start: where it loops back to.
        tracks.append(dict(id=ident, title=title, kind=kind, file=f'music/{file.name}', seconds=info['seconds'],
                           loop_start=info['loop_seconds'], source=note))
    unknown = sorted(p.stem for p in bgm.glob('sabgm_*.wav') if p.stem not in TRACKS)
    manifest = dict(tracks=tracks, provenance=dict(
        client=str(Path(source).name),
        encoding=f'Ogg Vorbis q{music_codec.QUALITY}, cut at the smpl loop end; loop_start from the smpl loop start',
        titles='bgm_tbl comments in system/t_music.cpp (8.5 client source), Big5/GBK mojibake reversed; '
               'untitled entries named after their play_bgm callers and map music markers.',
        untitled_extra=unknown))
    (folder / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n')
    size = sum((folder / Path(t['file']).name).stat().st_size for t in tracks)
    print(f'Imported {len(tracks)} radio tracks ({size // 1024} KB)' + (f'; not listed: {unknown}' if unknown else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='Client folder containing data/bgm (8.0 preferred)')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.output)
