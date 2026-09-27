"""Malformed-data and command coverage for the legacy pixel decoder."""
import unittest
from import_legacy import decode_rle

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

    def test_overrun(self):
        with self.assertRaises(ValueError):decode_rle(bytes([0xc3]),2)

    def test_incomplete(self):
        with self.assertRaises(ValueError):decode_rle(bytes([0xc1]),2)

if __name__=='__main__': unittest.main()
