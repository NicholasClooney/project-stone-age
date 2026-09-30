import struct
import tempfile
import unittest
import wave
from pathlib import Path

import music_codec


def write_wav(path: Path, frames: int, rate: int = 22050, loop=None) -> None:
    """8-bit stereo like the originals, with an optional smpl loop after the data."""
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(2)
        audio.setsampwidth(1)
        audio.setframerate(rate)
        audio.writeframes(bytes((128 + (i // 2) % 64) for i in range(frames * 2)))
    if loop:
        body = struct.pack('<9I', 0, 0, 1_000_000_000 // rate, 60, 0, 0, 0, 1, 0)
        body += struct.pack('<6I', 0, 0, loop[0], loop[1], 0, 0)
        chunk = b'smpl' + struct.pack('<I', len(body)) + body
        raw = bytearray(path.read_bytes() + chunk)
        raw[4:8] = struct.pack('<I', len(raw) - 8)
        path.write_bytes(bytes(raw))


class MusicCodecTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())

    def test_loop_points_come_from_the_smpl_chunk(self):
        wav = self.folder / 'sabgm_t0.wav'
        write_wav(wav, 30000, loop=(5000, 25000))
        self.assertEqual(music_codec.loop_points(wav), (5000, 25000))
        info = music_codec.layout(wav)
        # Like play_bgm: the buffer ends at the loop end and loops back to its start.
        self.assertEqual((info['frames'], info['loop_start']), (25000, 5000))
        self.assertAlmostEqual(info['loop_seconds'], 5000 / 22050, places=5)
        self.assertAlmostEqual(info['seconds'], 25000 / 22050, places=3)

    def test_a_track_without_a_loop_loops_whole(self):
        wav = self.folder / 'sabgm_t2.wav'
        write_wav(wav, 12000)
        self.assertIsNone(music_codec.loop_points(wav))
        self.assertEqual(music_codec.layout(wav)['frames'], 12000)
        self.assertEqual(music_codec.layout(wav)['loop_start'], 0)

    def test_a_loop_outside_the_audio_is_ignored(self):
        wav = self.folder / 'sabgm_x.wav'
        write_wav(wav, 12000, loop=(100, 50000))
        self.assertEqual((music_codec.layout(wav)['frames'], music_codec.layout(wav)['loop_start']), (12000, 0))

    def test_the_encoded_stream_ends_at_the_loop_end(self):
        try:
            import soundfile
        except ImportError:
            self.skipTest('soundfile (tools/requirements.txt) not installed')
        wav = self.folder / 'sabgm_t0.wav'
        write_wav(wav, 30000, loop=(5000, 25000))
        ogg = self.folder / 'sabgm_t0.ogg'
        music_codec.encode(wav, ogg)
        info = soundfile.info(str(ogg))
        self.assertEqual((info.format, info.subtype, info.samplerate, info.channels), ('OGG', 'VORBIS', 22050, 2))
        self.assertEqual(info.frames, 25000)
        self.assertLess(ogg.stat().st_size, wav.stat().st_size)


if __name__ == '__main__':
    unittest.main()
