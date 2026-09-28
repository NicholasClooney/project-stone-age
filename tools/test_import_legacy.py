"""Malformed-data and command coverage for the legacy pixel decoder."""
import tempfile
import unittest
from pathlib import Path
from import_legacy import data_file, decode_rle, palette_file

class RLETests(unittest.TestCase):
    def test_literal(self):
        self.assertEqual(decode_rle(bytes([3,7,8,9]),3),bytes([7,8,9]))

    def test_repeated_and_transparent(self):
        self.assertEqual(decode_rle(bytes([0x83,7,0xc2]),5),bytes([7,7,7,0,0]))

    def test_extended_literal(self):
        self.assertEqual(decode_rle(bytes([0x10,3,7,8,9]),3),bytes([7,8,9]))

    def test_extended_repeat_color_precedes_count(self):
        self.assertEqual(decode_rle(bytes([0x91,42,0]),256),bytes([42])*256)

    def test_large_transparent(self):
        self.assertEqual(decode_rle(bytes([0xe0,1,0]),256),bytes(256))

    def test_bad_command(self):
        with self.assertRaises(ValueError):decode_rle(bytes([0x31]),1)

    def test_truncated_literal(self):
        with self.assertRaises(ValueError):decode_rle(bytes([3,7]),3)

    def test_truncated_count(self):
        with self.assertRaises(ValueError):decode_rle(bytes([0xd1]),1)

    def test_overrun_is_clipped_like_the_original(self):
        # unpack.cpp writes runs unbounded and keeps width*height bytes.
        self.assertEqual(decode_rle(bytes([0x83,7]),2),bytearray([7,7]))
        self.assertEqual(decode_rle(bytes([0xc3]),2),bytearray([0,0]))
        self.assertEqual(decode_rle(bytes([0x03,1,2,3]),2),bytearray([1,2]))
        with self.assertRaises(ValueError):decode_rle(bytes([0x03,1]),1)

    def test_incomplete(self):
        with self.assertRaises(ValueError):decode_rle(bytes([0xc1]),2)


class DataFileTests(unittest.TestCase):
    def folder(self, names):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        (root/'pal').mkdir()
        for name in names: (root/name).write_bytes(b'')
        return root

    def test_2_5_names(self):
        data = self.folder(['adrn_15.bin', 'real_15.bin', 'spradrn_5.bin', 'spr_4.bin', 'sound_1.bin', 'sound_3.bin', 'pal/Palet_0.sap', 'pal/Palet_1.sap', 'pal/Palet_10.sap'])
        self.assertEqual([data_file(data, stem).name for stem in ('adrn', 'real', 'spradrn', 'spr')], ['adrn_15.bin', 'real_15.bin', 'spradrn_5.bin', 'spr_4.bin'])
        self.assertEqual(palette_file(data).name, 'Palet_1.sap')

    def test_8_0_names_pick_the_highest_revision_exactly(self):
        # adrntrue_5/realtrue_13 are other formats; numbers compare as integers.
        data = self.folder(['adrn_136.bin', 'adrn_99.bin', 'adrntrue_5.bin', 'real_136.bin', 'realtrue_13.bin', 'spradrn_115.bin', 'SPR_115.BIN', 'pal/PALET_1.SAP', 'pal/PALET_10.SAP'])
        self.assertEqual(data_file(data, 'adrn').name, 'adrn_136.bin')
        self.assertEqual(data_file(data, 'real').name, 'real_136.bin')
        self.assertEqual(data_file(data, 'spr').name, 'SPR_115.BIN')
        self.assertEqual(palette_file(data).name, 'PALET_1.SAP')

    def test_missing_files_are_errors(self):
        data = self.folder(['adrntrue_5.bin'])
        with self.assertRaises(FileNotFoundError): data_file(data, 'adrn')
        with self.assertRaises(FileNotFoundError): palette_file(data)

if __name__=='__main__': unittest.main()
