"""Shared-palette map images (tools/palette_images.py)."""
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from palette_images import convert


def rgba(colours, alpha=255):
    image = Image.new("RGBA", (4, 3), (0, 0, 0, 0))
    for i, colour in enumerate(colours):
        image.putpixel((i % 4, i // 4), colour + (alpha,))
    return image


class PaletteImagesTest(unittest.TestCase):
    def test_images_share_one_palette_and_stay_pixel_identical(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            before = {
                "1.png": rgba([(10, 20, 30), (40, 50, 60)]),
                "2.png": rgba([(40, 50, 60), (255, 0, 255), (7, 7, 7)]),
                "3.png": Image.new("RGBA", (2, 2), (0, 0, 0, 0)),
            }
            for name, image in before.items():
                image.save(folder / name)
            self.assertEqual(convert(folder), (3, 0, 0))
            palettes = set()
            for name, image in before.items():
                with Image.open(folder / name) as written:
                    self.assertEqual(written.mode, "P")
                    self.assertEqual(written.info.get("transparency"), 0)
                    palettes.add(tuple(written.getpalette()[:768]))
                    after = written.convert("RGBA")
                visible = lambda im: [p if p[3] else (0, 0, 0, 0) for p in im.getdata()]
                self.assertEqual(visible(after), visible(image), name)
            self.assertEqual(len(palettes), 1)
            # The key colour avoids colours the images use ((255, 0, 255) here).
            self.assertNotEqual(palettes.pop()[:3], (255, 0, 255))
            mtime = (folder / "1.png").stat().st_mtime_ns
            self.assertEqual(convert(folder), (0, 3, 0))
            self.assertEqual((folder / "1.png").stat().st_mtime_ns, mtime)

    def test_partial_alpha_stays_rgba_and_others_still_convert(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            rgba([(1, 1, 1)], alpha=128).save(folder / "soft.png")
            rgba([(2, 2, 2)]).save(folder / "hard.png")
            self.assertEqual(convert(folder), (1, 0, 1))
            with Image.open(folder / "soft.png") as image:
                self.assertEqual(image.mode, "RGBA")

    def test_more_than_255_colours_keeps_everything_rgba(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            for n in range(22):
                rgba([(n, i, 0) for i in range(12)]).save(folder / f"{n}.png")
            self.assertEqual(convert(folder), (0, 0, 22))


if __name__ == "__main__":
    unittest.main()
