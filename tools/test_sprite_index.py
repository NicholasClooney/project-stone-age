"""Original SPRADRN override order shared by exploration and battle decoders."""
import json
import struct
import unittest
from pathlib import Path

from import_legacy import Archive
from import_battle import animations
from import_encounter_art import load_sprite


class SpriteArchive:
    def __init__(self, records):
        index, raw = bytearray(), bytearray()
        for sprite, clips in records:
            index += struct.pack('<IIHH', sprite, len(raw), len(clips), 0)
            for (action, direction), bitmap in clips.items():
                raw += struct.pack('<HHII', direction, action, 800, 1)
                raw += struct.pack('<IhhH', bitmap, -2, 3, 73)
        self.raw = bytes(index), bytes(raw)
        self.entries = {bitmap: {} for _, clips in records for bitmap in clips.values()}
        self.source = Path('fixture')
        self.cache = {}

    def sprite_bytes(self):
        return self.raw

    def image(self, bitmap):
        return object()


def clips(bitmap):
    return {(a, d): bitmap for a in (0, 1, 2, 3, 4, 10) for d in range(8)}


class SpriteIndexTests(unittest.TestCase):
    def test_last_record_overrides_both_entry_points(self):
        source = SpriteArchive([(101154, clips(11)), (999, clips(33)), (101154, clips(22))])
        battle = animations(source, 101154)
        walking = Archive.animations(source, 101154)
        self.assertEqual(battle['3_1'], walking['3_1'])
        self.assertEqual(battle['3_1']['frames'], [{'image': 22, 'x': -2, 'y': 3, 'sound': 73}])
        self.assertEqual(battle['0_1']['frames'][0]['image'], 22)
        self.assertEqual(set(walking), {f'{a}_{d}' for a in (3, 4) for d in range(8)})

    def test_partial_override_does_not_merge_or_retain_old_actions(self):
        source = SpriteArchive([(101154, clips(11)), (101154, {(3, 1): 22})])
        self.assertEqual(set(animations(source, 101154)), {'3_1'})
        self.assertEqual(set(Archive.animations(source, 101154)), {'3_1'})

    def test_incomplete_last_record_uses_later_client_without_reverting_to_first(self):
        old = SpriteArchive([(101154, clips(11)), (101154, {(3, 1): 22})])
        later = SpriteArchive([(101154, clips(33))])
        actions, images, client = load_sprite([old, later], 101154, True)
        self.assertEqual(client, 1)
        self.assertEqual(actions['3_1']['frames'][0]['image'], 33)
        self.assertEqual(set(images), {33})

    def test_corrected_complete_last_record_keeps_primary_client(self):
        old = SpriteArchive([(101154, {(3, 1): 11}), (101154, clips(22))])
        later = SpriteArchive([(101154, clips(33))])
        actions, _, client = load_sprite([old, later], 101154, True)
        self.assertEqual(client, 0)
        self.assertEqual(actions['3_1']['frames'][0]['image'], 22)

    def test_missing_sprite_is_explicit(self):
        source = SpriteArchive([(999, clips(11))])
        for decode in (animations, Archive.animations):
            with self.assertRaisesRegex(ValueError, 'Missing sprite 101154'):
                decode(source, 101154)


ROOT = Path(__file__).resolve().parents[1]
SOURCE25 = ROOT / '.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5'
SOURCE80 = ROOT / '.tools/legacy/extracted/SA8.0-20260803'


@unittest.skipUnless((SOURCE25 / 'data/spradrn_5.bin').exists() and
                     (SOURCE80 / 'data/spradrn_115.bin').exists(), 'local original clients not installed')
class OriginalSpriteIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.archives = [Archive(SOURCE25), Archive(SOURCE80)]

    @classmethod
    def tearDownClass(cls):
        for source in cls.archives:
            source.real.close()

    def test_four_nianshou_match_both_original_clients_and_pixels(self):
        expected = {101152: 233685, 101153: 233189, 101154: 233437, 101155: 233933}
        signatures = set()
        for sprite, first in expected.items():
            old, later = self.archives
            a, b = animations(old, sprite), animations(later, sprite)
            self.assertEqual(a, b, sprite)
            self.assertEqual(a['3_1']['frames'][0]['image'], first)
            self.assertEqual(Archive.animations(old, sprite)['3_1'], a['3_1'])
            signatures.add(json.dumps(a, sort_keys=True))
            _, images, client = load_sprite(self.archives, sprite, True)
            self.assertEqual(client, 0, sprite)
            self.assertEqual(len(images), 248)
            for bitmap in images:
                x, y = old.image(bitmap), later.image(bitmap)
                self.assertEqual((x.size, x.tobytes()), (y.size, y.tobytes()), bitmap)
            for source in self.archives:
                source.cache.clear()
        self.assertEqual(len(signatures), 4)

    @unittest.skipUnless((ROOT / "client/assets/legacy/battle/pets/101866.json").exists(),
                         "local imported pet art not installed")
    def test_other_duplicate_records_do_not_change_imported_art(self):
        root = ROOT / 'client/assets/legacy/battle'
        for sprite in (101866, 101990, 101991):
            source = json.loads((root / f'pets/{sprite}.json').read_text())
            actions, _, client = load_sprite(self.archives, sprite, True)
            self.assertEqual(client, 1)
            self.assertEqual(actions, source['characters'][str(sprite)], sprite)
        # The 2.5 101151 correction is followed by its original static record;
        # it is not a catalog pet and must not acquire a complete battle set.
        self.assertEqual(animations(self.archives[0], 101151), animations(self.archives[1], 101151))
        self.assertEqual(len(animations(self.archives[0], 101151)), 1)


if __name__ == '__main__':
    unittest.main()
