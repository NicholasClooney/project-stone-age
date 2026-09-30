"""Ogg Vorbis encoding of the original background music, keeping its loop.

The original WAVs (data/bgm/sabgm_*.wav) carry a RIFF `smpl` chunk with one
forward loop: play_bgm (system/t_music.cpp, BGM_AUTO_LOOP) plays from the start,
stops the buffer at the loop's end sample and jumps back to its start sample,
so a track with an intro plays the intro once. Tracks without the chunk loop
whole. Here the audio after the loop end is cut off and the loop start is
returned, so the game sets AudioStreamOggVorbis.loop_offset to it
(scripts/music_tracks.gd) and the stream loops exactly like the original.

Vorbis via libsndfile (the `soundfile` wheel bundles libvorbis, see
tools/requirements.txt) at QUALITY; ffmpeg's built-in encoder is the
fallback. The original WAVs stay in the extracted client folders for a
lossless option later.
"""
import shutil
import struct
import subprocess
import wave
from pathlib import Path

# Vorbis quality (-q 0 to 10). The originals are 22 kHz, mostly 8-bit, so q6
# is transparent to them at about 80 to 110 kbps.
QUALITY = 6


def loop_points(wav: Path) -> tuple:
    """(start, end) sample frames of the first `smpl` loop, or None."""
    raw = wav.read_bytes()
    at = 12
    while at + 8 <= len(raw):
        ident = raw[at:at + 4]
        size = struct.unpack('<I', raw[at + 4:at + 8])[0]
        body = raw[at + 8:at + 8 + size]
        if ident == b'smpl' and len(body) >= 36:
            count = struct.unpack('<I', body[28:32])[0]
            if count and len(body) >= 60:
                _cue, _kind, start, end, _fraction, _plays = struct.unpack('<6I', body[36:60])
                return (start, end)
        at += 8 + size + (size & 1)
    return None


def layout(wav: Path) -> dict:
    """What the encoded stream holds: frames kept, loop start, rate, seconds.

    Like play_bgm, the loop end is where playback wraps (frames [0, end) are
    kept); a loop outside the audio is ignored.
    """
    with wave.open(str(wav)) as audio:
        frames, rate = audio.getnframes(), audio.getframerate()
    start, end = 0, frames
    points = loop_points(wav)
    if points and 0 <= points[0] < points[1] <= frames:
        start, end = points
    return dict(frames=end, loop_start=start, rate=rate, seconds=round(end / rate, 3), loop_seconds=round(start / rate, 6))


def encode(wav: Path, ogg: Path, quality: int = QUALITY) -> dict:
    """Writes wav (cut at its loop end) to ogg; returns layout(wav).

    Raises RuntimeError when no Vorbis encoder is available."""
    info = layout(wav)
    ogg.parent.mkdir(parents=True, exist_ok=True)
    try:
        import soundfile
    except ImportError:
        soundfile = None
    if soundfile is not None:
        data, rate = soundfile.read(str(wav), frames=info['frames'], dtype='float32', always_2d=True)
        # libsndfile maps compression level 0..1 to Vorbis quality 1..0.
        soundfile.write(str(ogg), data, rate, format='OGG', subtype='VORBIS', compression_level=1.0 - quality / 10.0)
        return info
    if shutil.which('ffmpeg'):
        result = subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', str(wav), '-af', f'atrim=end_sample={info["frames"]}',
                                 '-strict', '-2', '-c:a', 'vorbis', '-q:a', str(quality), str(ogg)], capture_output=True, text=True)
        if result.returncode == 0 and ogg.exists() and ogg.stat().st_size > 0:
            return info
        raise RuntimeError(f'ffmpeg could not write Vorbis for {wav.name}: {result.stderr.strip()}')
    raise RuntimeError('No Vorbis encoder: install tools/requirements.txt (soundfile) or ffmpeg')
