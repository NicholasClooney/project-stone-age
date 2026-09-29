import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import import_encounter_art as art


class FakeImage:
    def __init__(self, pixels):
        self.pixels = pixels

    def tobytes(self):
        return self.pixels

    def save(self, path):
        Path(path).write_bytes(self.pixels)


class FakeArchive:
    """entries: bitmap -> pixels; sprites: sprite -> actions (or missing)."""
    def __init__(self, name, entries, sprites):
        self.source = name
        self.entries = {b: dict(x=0, y=0, w=1, h=len(p)) for b, p in entries.items()}
        self.pixels = entries
        self.sprites = sprites
        self.cache = {}

    def image(self, bitmap):
        return FakeImage(self.pixels[bitmap])


def actions(bitmap):
    return {f'{a}_{d}': {'duration_ms': 100, 'frames': [{'image': bitmap, 'x': 0, 'y': 0, 'sound': 0}]} for a in (0, 1, 2, 3, 4, 10) for d in range(8)}


def fake_animations(archive, sprite):
    if sprite not in archive.sprites:
        raise ValueError(f'Missing sprite {sprite}')
    return json.loads(json.dumps(archive.sprites[sprite]))


class EncounterArtTests(unittest.TestCase):
    def test_every_pet_template_is_wanted(self):
        catalog = {'templates': {'1': {'sprite': 100250, 'pet_flag': 1}, '2': {'sprite': 100300, 'pet_flag': 0},
                                 '10417': {'sprite': 101869, 'pet_flag': 1, 'stats_known': False}}}
        self.assertEqual(art.pet_sprites(catalog), {100250, 101869})

    def test_later_client_bitmaps_keep_their_number_only_when_the_picture_matches(self):
        old = FakeArchive('2.5', {1: b'a', 2: b'b'}, {})
        new = FakeArchive('8.0', {1: b'a', 2: b'other', 3: b'c'}, {})
        self.assertEqual(art.renumbering(old, new, {1, 2, 3}), {1: 1, 2: art.RENUMBER + 2, 3: 3})

    def test_run_keeps_world_sprites_in_the_manifest_and_other_pets_in_their_own_files(self):
        old = FakeArchive('2.5', {1: b'a', 2: b'b'}, {100250: actions(1)})
        new = FakeArchive('8.0', {2: b'other', 5: b'e'}, {101869: actions(2), 101870: actions(5)})
        catalog = {'areas': [{'map_id': 1000, 'event_now': -1, 'event_end': -1, 'groups': [{'id': 1, 'weight': 1}]}],
                   'groups': {'1': {'requires_item': -1, 'excludes_item': -1, 'enemies': [{'id': 1, 'weight': 1}]}},
                   'enemies': {'1': {'template_id': 1}},
                   'templates': {'1': {'sprite': 100250, 'pet_flag': 1},
                                 '10417': {'sprite': 101869, 'pet_flag': 1, 'stats_known': False},
                                 '10418': {'sprite': 101870, 'pet_flag': 1, 'stats_known': False},
                                 '20': {'sprite': 999999, 'pet_flag': 1}}}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for part in ('encounters', 'world', 'battle'):
                (root / part).mkdir()
            (root / 'encounters/catalog.json').write_text(json.dumps(catalog))
            (root / 'world/manifest.json').write_text(json.dumps({'maps': {'1000': {}}}))
            (root / 'battle/manifest.json').write_text(json.dumps({'characters': {}, 'images': {}}))
            archives = {'2.5': old, '8.0': new}
            with mock.patch.object(art, 'Archive', side_effect=lambda source: archives[source]), \
                    mock.patch.object(art, 'animations', side_effect=fake_animations), \
                    mock.patch.object(art, 'SPECIAL_PETS', []), mock.patch('builtins.print'):
                art.run('2.5', root, '8.0')
            battle = json.loads((root / 'battle/manifest.json').read_text())
            report = json.loads((root / 'encounters/art-coverage.json').read_text())
            self.assertEqual(set(battle['characters']), {'100250'})
            self.assertEqual(battle['extra_sprites'], {'101869': 'pets/101869.json', '101870': 'pets/101870.json'})
            extra = json.loads((root / 'battle/pets/101869.json').read_text())
            renumbered = art.RENUMBER + 2
            self.assertEqual(extra['characters']['101869']['3_1']['frames'][0]['image'], renumbered)
            self.assertIn(str(renumbered), extra['images'])
            self.assertEqual((root / f'battle/images/{renumbered}.png').read_bytes(), b'other')
            self.assertEqual((root / 'battle/images/5.png').read_bytes(), b'e')
            self.assertEqual(report['sources'], {'100250': '2.5', '101869': '8.0', '101870': '8.0'})
            self.assertEqual(report['extra'], [101869, 101870])
            self.assertIn('999999', report['unavailable'])
            self.assertEqual(report['counts']['by_source'], {'2.5': 1, '8.0': 2})


if __name__ == '__main__':
    unittest.main()
