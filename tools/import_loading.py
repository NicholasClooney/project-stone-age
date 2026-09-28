"""Import the art and music of the web build's waiting screen.

  image  CG_TITLE_NOW_LOADING (logical graphic 29019, anim_tbl.h), the
         original 640x480 "NOW LOADING...." title-sequence screen.
  music  data/bgm/sabgm_s1.wav, bgm_tbl entry 2, which login.cpp plays once
         the character list has downloaded (the original's own waiting room).

The track is transcoded to Ogg Vorbis (about 260 KB instead of 1.3 MB) when
ffmpeg is available, otherwise copied as WAV (Godot then stores it as QOA,
about 0.5 MB). Both land in client/assets/legacy/loading/, which
plan_web_packs.py puts in the small `loading` pack the page fetches first.
"""
import argparse
import shutil
import subprocess
from pathlib import Path

from import_legacy import Archive

IMAGE = 29019
TRACK = 'sabgm_s1'


def transcode(wav: Path, folder: Path) -> Path:
    """Ogg Vorbis via ffmpeg's built-in encoder, or the original WAV."""
    ogg = folder / f'{TRACK}.ogg'
    if shutil.which('ffmpeg'):
        result = subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(wav), '-strict', '-2',
                                 '-c:a', 'vorbis', '-q:a', '4', str(ogg)], capture_output=True, text=True)
        if result.returncode == 0 and ogg.exists() and ogg.stat().st_size > 0:
            (folder / f'{TRACK}.wav').unlink(missing_ok=True)
            return ogg
        print('ffmpeg could not write Vorbis; keeping the WAV:', result.stderr.strip())
    ogg.unlink(missing_ok=True)
    target = folder / f'{TRACK}.wav'
    shutil.copyfile(wav, target)
    return target


def run(source, output):
    source, output = Path(source), Path(output)
    folder = output / 'loading'
    folder.mkdir(parents=True, exist_ok=True)
    archive = Archive(source)
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    if IMAGE not in logical:
        raise ValueError(f'Graphic {IMAGE} (CG_TITLE_NOW_LOADING) is absent')
    image = archive.image(logical[IMAGE]).convert('RGB')
    # The bitmap's outermost pixels are partly black, which shows as a thin
    # frame once the screen is letterboxed; paint them the image's own background.
    background = image.getpixel((image.width // 2, 1))
    for x in range(image.width):
        for y in (0, image.height - 1):
            if image.getpixel((x, y)) == (0, 0, 0): image.putpixel((x, y), background)
    for y in range(image.height):
        for x in (0, image.width - 1):
            if image.getpixel((x, y)) == (0, 0, 0): image.putpixel((x, y), background)
    image.save(folder / 'now-loading.png', optimize=True)
    track = transcode(source / 'data/bgm' / f'{TRACK}.wav', folder)
    print(f'Imported waiting screen {image.width}x{image.height} and {track.name} ({track.stat().st_size // 1024} KB)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.source, args.output)
