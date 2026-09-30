import base64
import json
import struct
import tempfile
import unittest
from pathlib import Path

import split_manifests


def frame(image, x=0, y=0, sound=0):
    return {'image': image, 'x': x, 'y': y, 'sound': sound}


def complete(images):
    """Animations with every battle action and direction, drawing `images`."""
    return {f'{a}_{d}': {'duration_ms': 600, 'frames': [frame(i) for i in images]}
            for a in split_manifests.BATTLE_ACTIONS for d in range(8)}


class SplitManifestsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'battle/pets').mkdir(parents=True)
        (self.root / 'riding').mkdir()
        (self.root / 'characters').mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, data):
        (self.root / name).write_text(json.dumps(data))

    def read(self, name):
        return json.loads((self.root / name).read_text())

    def test_battle_sprites_get_compact_files_and_an_index(self):
        images = {str(i): {'x': -i, 'y': -2 * i, 'w': 10, 'h': 20} for i in (1, 2, 3)}
        club = complete([1, 3])
        club['0_3']['frames'][0] = frame(1, 4, 5, 10001)
        self.write('battle/manifest.json', {
            'player_id': '100000', 'frame_sounds': {'1': 'audio/a.wav'}, 'ui': {}, 'audio': {'bgm': 'b.wav'},
            'equipment_variants': {'club': {'100000': '100002'}},
            'characters': {'100000': complete([1, 2]), '100002': club, '100005': {'3_0': {'duration_ms': 100, 'frames': [frame(2)]}}},
            'images': images,
            'sheets': {'100000': {'files': ['sheets/100000.png'], 'frames': {'1': [0, 0, 0, 10, 20], '2': [0, 11, 0, 10, 20]}},
                       '100002': {'files': ['sheets/100002.png'], 'frames': {'3': [0, 0, 0, 10, 20]}},
                       '100005': {'files': ['sheets/100005.png'], 'frames': {}}},
            'extra_sprites': {'101869': 'pets/101869.json', '101870': 'pets/101870.json'}})
        self.write('battle/pets/101869.json', {'characters': {'101869': complete([7])},
                                               'images': {'7': {'x': 1, 'y': 2, 'w': 3, 'h': 4}},
                                               'sheets': {'101869': {'files': ['sheets/101869.png'], 'frames': {'7': [0, 5, 6, 3, 4]}}}})
        # A stale file from an earlier split is removed.
        (self.root / 'battle/sprites').mkdir()
        (self.root / 'battle/sprites/999.json').write_text('{}')
        split_manifests.split_battle(self.root)

        index = self.read('battle/index.json')
        self.assertEqual(index['player_id'], '100000')
        self.assertEqual(index['frame_sounds'], {'1': 'audio/a.wav'})
        self.assertNotIn('characters', index)
        self.assertEqual(index['sprites'], {'100000': ['sheets/100000.png'], '100002': False, '100005': False})
        self.assertEqual(index['extra_sprites'], {'101869': ['sheets/101869.png']})
        self.assertEqual(sorted(p.name for p in (self.root / 'battle/sprites').iterdir()),
                         ['100000.json', '100002.json', '100005.json', '101869.json'])

        club_file = self.read('battle/sprites/100002.json')
        self.assertEqual(club_file['animations']['0_3'][:5], [600, 1, 4, 5, 10001])
        # Bitmap 1 is drawn from 100000's sheet, bitmap 3 from its own.
        self.assertEqual(club_file['files'], ['sheets/100000.png', 'sheets/100002.png'])
        self.assertEqual(club_file['bitmaps'], [1, -1, -2, 10, 20, 0, 0, 0, 3, -3, -6, 10, 20, 1, 0, 0])
        # Its own sheet lacks bitmap 2, so it is drawn from 100000's sheet.
        self.assertEqual(self.read('battle/sprites/100005.json')['bitmaps'], [2, -2, -4, 10, 20, 0, 11, 0])
        pet = self.read('battle/sprites/101869.json')
        self.assertEqual(pet['bitmaps'], [7, 1, 2, 3, 4, 0, 5, 6])

    def test_riding_and_characters(self):
        self.write('riding/manifest.json', {
            'pairs': {'100000:100352': {'sprite': 101000}}, 'names': {'100352': 'x'}, 'frame_sounds': {'62': 'audio/a.wav'},
            'characters': {'101000': {'3_0': {'duration_ms': 100, 'frames': [frame(9, 1, 1)]}}},
            'images': {'9': {'x': 0, 'y': 0, 'w': 2, 'h': 2}},
            'sheets': {'101000': {'files': ['sheets/101000.png'], 'frames': {'9': [0, 1, 1, 2, 2]}}}})
        self.write('characters/catalog.json', {
            'choices': [{'id': '100000'}], 'skipped': [],
            'characters': {'100000': {'3_0': {'duration_ms': 100, 'frames': [frame(5)]}}},
            'images': {'5': {'x': 0, 'y': 0, 'w': 2, 'h': 2}}, 'sheets': {}})
        split_manifests.split(['riding', 'characters'], self.root)
        riding = self.read('riding/index.json')
        self.assertEqual(riding['composites'], {'101000': True})
        self.assertEqual(riding['pairs'], {'100000:100352': {'sprite': 101000}})
        self.assertNotIn('images', riding)
        self.assertEqual(self.read('riding/composites/101000.json')['animations'], {'3_0': [100, 9, 1, 1, 0]})
        characters = self.read('characters/index.json')
        self.assertEqual(characters, {'choices': [{'id': '100000'}], 'skipped': [], 'characters': {'100000': True}})
        self.assertEqual(self.read('characters/art/100000.json')['bitmaps'], [5, 0, 0, 2, 2, -1, 0, 0])

    def test_backgrounds_become_packed_lookups(self):
        self.write('battle/backgrounds.json', {
            'ground_to_battlefields': {'0': [1, 2, 201], '1': [1, 2, 201], '3': [5, 5, 5]},
            'bitmap_to_ground': {'129': '4', '12': 3},
            'backgrounds': {'1': {'path': 'backgrounds/1.png', 'sha256': 'x'}}, 'unavailable': {}, 'provenance': 'p'})
        split_manifests.split_backgrounds(self.root)
        result = self.read('battle/battlefields.json')
        self.assertEqual(result['choices'], [0, 0, 0, 1, 2, 201, 5, 5, 5])
        self.assertEqual(list(struct.unpack('<4H', base64.b64decode(result['ground_choice']))), [1, 1, 0, 2])
        self.assertEqual((result['bitmaps'], result['grounds']), ([12, 129], [3, 4]))
        self.assertEqual(result['backgrounds'], {'1': 'backgrounds/1.png'})

    def test_nothing_to_split_is_not_an_error(self):
        split_manifests.split(split_manifests.KINDS, self.root)
        self.assertFalse((self.root / 'battle/index.json').exists())


if __name__ == '__main__':
    unittest.main()
