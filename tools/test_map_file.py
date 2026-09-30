"""The compact map file round-trips the importers' JSON shape."""
import json
from pathlib import Path
import tempfile
import unittest
from map_file import encode, decode, load_map, same_map, convert_world, save_map


def sample():
    # Ground in the importers' order (not row order), a cell without ground,
    # objects outside the grid order and a multi-byte name.
    return dict(map_id=7, name='吉鲁岛', origin=[1, 2], width=3, height=2,
                ground=[[2, 1, 126271], [0, 0, 13], [1, 0, 14], [0, 1, 15], [2, 0, 16]],
                objects=[[2, 1, 4910], [0, 0, 5161], [2, 1, 4910]],
                blocked=[1, 0, 0, 1, 0, 1], music_markers=[dict(cell=[1, 1], tone=45, music='world/audio/sabgm_f0.wav')],
                images={'13': dict(x=-32, y=-24, w=64, h=47, ex=1, ey=1, hit=1, priority=0)},
                map_colors={'13': [1, 2, 3]}, characters={'100000': {}})


class MapFileTests(unittest.TestCase):
    def test_round_trip_keeps_every_cell_object_and_field(self):
        data = sample()
        back = decode(encode(data))
        self.assertTrue(same_map(data, back))
        self.assertEqual(back['ground'][0], [0, 0, 13])
        self.assertNotIn([1, 1, 0], back['ground'])
        self.assertEqual(back['objects'], data['objects'])
        self.assertEqual(back['name'], '吉鲁岛')
        self.assertEqual(decode(encode(data), header_only=True)['images'], data['images'])

    def test_layout_is_little_endian_grids_after_the_header(self):
        raw = encode(sample())
        self.assertEqual(raw[:8], b'SAMAP\0\1\0')
        header = int.from_bytes(raw[8:12], 'little')
        offset = 12+header
        self.assertEqual(int.from_bytes(raw[offset:offset+4], 'little'), 6)
        self.assertEqual(int.from_bytes(raw[offset+4:offset+8], 'little'), 13)
        blocked = offset+4+24
        self.assertEqual(raw[blocked+4:blocked+10], bytes([1, 0, 0, 1, 0, 1]))

    def test_rejects_what_the_game_could_not_read(self):
        for change in (dict(blocked=[0]*5), dict(ground=[[3, 0, 13]]), dict(ground=[[0, 0, 0]]), dict(objects=[[1, 2]])):
            with self.subTest(change=change), self.assertRaises(ValueError):
                encode({**sample(), **change})
        with self.assertRaises(ValueError):
            decode(encode(sample())+b'\0')

    def test_convert_world_replaces_json_and_updates_the_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'world').mkdir()
            (root/'world/7.json').write_text(json.dumps(sample()))
            (root/'world/manifest.json').write_text(json.dumps(dict(maps={'7': dict(path='world/7.json', name='x')})))
            self.assertEqual(convert_world(root), 1)
            self.assertFalse((root/'world/7.json').exists())
            manifest = json.loads((root/'world/manifest.json').read_text())
            self.assertEqual(manifest['maps']['7']['path'], 'world/7.map')
            self.assertTrue(same_map(sample(), load_map(root/'world/7.map')))
            self.assertEqual(convert_world(root), 0)

    def test_load_map_reads_both_formats(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder)/'a.json').write_text(json.dumps(sample()))
            save_map(Path(folder)/'a.map', sample())
            self.assertTrue(same_map(load_map(Path(folder)/'a.json'), load_map(Path(folder)/'a.map')))


if __name__ == '__main__':
    unittest.main()
