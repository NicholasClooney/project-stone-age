import struct
import unittest
from import_cursor import decode_cursor


def fixture():
    # 2x2, bottom-up RGB rows padded to four bytes, followed by bottom-up AND rows.
    pixels = bytes([255,0,0, 0,255,0, 0,0, 0,0,255, 255,255,255, 0,0])
    mask = bytes([0x40,0,0,0, 0x80,0,0,0])
    dib = struct.pack('<IiiHHIIiiII',40,2,4,1,24,0,16,0,0,0,0)+pixels+mask
    return struct.pack('<HHHBBBBHHII',0,2,1,2,2,0,0,1,0,len(dib),22)+dib


class CursorTest(unittest.TestCase):
    def test_mask_orientation_and_hotspot(self):
        image, hotspot = decode_cursor(fixture())
        self.assertEqual(hotspot,[1,0])
        self.assertEqual(image.getpixel((0,0)),(255,0,0,0))
        self.assertEqual(image.getpixel((1,0)),(255,255,255,255))
        self.assertEqual(image.getpixel((0,1)),(0,0,255,255))
        self.assertEqual(image.getpixel((1,1)),(0,255,0,0))

    def test_truncated_bitmap_rejected(self):
        with self.assertRaises(ValueError): decode_cursor(fixture()[:-1])

    def test_invalid_hotspot_rejected(self):
        data = bytearray(fixture())
        struct.pack_into('<H',data,10,2)
        with self.assertRaises(ValueError): decode_cursor(data)

    def test_compressed_bitmap_rejected(self):
        data = bytearray(fixture())
        struct.pack_into('<I',data,38,1)
        with self.assertRaises(ValueError): decode_cursor(data)

if __name__ == '__main__': unittest.main()
