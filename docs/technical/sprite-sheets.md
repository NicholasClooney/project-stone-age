# Sprite sheets

The original client stores every animation frame as its own bitmap. Importing them one PNG per frame made the Godot project hold tens of thousands of tiny files. The importers now pack the frames of one animated thing (a rider and mount composite, first) into one sprite sheet, and the game cuts frames out of it.

## Why per-frame PNGs were slow

Every PNG under `client/` costs far more than its pixels:

- **Godot import.** Each file gets its own `.import` file, uid and compressed `.ctex`, and is processed on its own. With the 8.0 riding data (69,952 frames) the first import took about 40 minutes.
- **Web packs.** A `riding-<id>` pack held a few hundred small files, which made building and downloading packs slow.
- **Runtime.** Every frame was a separate texture load the first time it was drawn.

## Packing (`tools/sprite_sheets.py`)

`pack_sheets(frames)` shelf-packs a composite's frames into as few sheets as fit:

- Frames are sorted tallest first, then widest, and laid left to right in rows ("shelves"). Frames of one composite are similar in size, so rows waste little space, and packing is fast.
- The sheet width is the next power of two at or above about 1.1 times the square root of the total area, capped at 4096 px. When a sheet would grow past 4096 px high, a second sheet starts. 4096 px is safe for every GPU the game targets, WebGL and Vision Pro included. No riding composite needed a second sheet.
- Each frame has 1 px of transparent padding on its right and bottom, so a neighbour never bleeds into a scaled or filtered frame.
- A frame larger than a sheet is refused rather than cropped.

## Lossless 256-colour sheets

The original art is 8-bit palette art with on/off transparency. Every riding sheet has about 200 to 220 colours and only fully transparent or fully opaque pixels, so `to_palette(sheet)` saves it as an 8-bit palette PNG without losing anything:

- Index 0 is transparent (a key colour none of the frames use); the sheet's colours follow in order. Unused entries repeat a real colour, so no pixel can map to the transparent index by accident.
- It only converts when that is exact: more than 255 colours, or any partly transparent pixel, keeps the sheet RGBA.
- `tools/test_sprite_sheets.py` checks that a palette sheet shows exactly the same visible pixels as the RGBA one (fully transparent pixels may carry a different hidden colour) and that partial alpha stays RGBA.

One byte per pixel instead of four cut the riding sheets from 795 MB (RGBA) to 234 MB and made writing them faster.

## Manifest

`client/assets/legacy/riding/manifest.json` keeps `characters` (animations by composite) and `images` (each bitmap's draw offset `x`, `y` and size `w`, `h`) and adds:

```json
"sheets": {
  "101309": {
    "files": ["sheets/101309.png"],
    "frames": {"123456": [0, 17, 240, 64, 80]}
  }
}
```

`frames` maps a bitmap id to `[sheet, x, y, w, h]`: the index into `files` and the frame's rectangle in that sheet. A bitmap used by several composites is copied into each composite's sheet, so a composite never needs another composite's file.

## Runtime

`client/scripts/sheet_frames.gd` `texture(folder, sheets, key, bitmap)` (used by `riding.gd` `frame_texture(composite, bitmap)`) returns an `AtlasTexture` whose atlas is the sheet and whose region is the frame's rectangle. Sheets and frames are cached in static dictionaries, so each sheet loads once and each frame object is made once. When a sheet is not available yet (its web pack is still downloading) it returns `null` and caches nothing, so the next draw tries again. `legacy_actor.gd` (field) and `battle_view.gd` (battles) draw mounted frames through it.

## Web packs

`tools/plan_web_packs.py` puts each composite's sheet file(s) in its `riding-<id>` pack. Mounting or a mounted battle waits for that one pack.

## Measured (8.0 riding data, M-series Mac)

| | Per-frame PNGs | Sheets |
| --- | --- | --- |
| Files | 69,952 | 241 |
| Source size | 1.1 GB | 234 MB |
| `import_riding.py` | about 6 min | under 2 min |
| Godot import | about 40 min | 28 s |
| `riding-<id>` web packs | hundreds of files each | one sheet each, 1.5 MB average, 2.9 MB largest, 355 MB in total |

## Trade-offs

- **The palette is lost in the build.** Godot imports the sheet as a full-colour lossless texture, so the web packs (355 MB) are larger than the palette PNGs (234 MB). Keeping palette data in the build would need a custom texture format and shader; not worth it yet.
- **Video memory.** A loaded sheet occupies its full size, up to about 23 MB for a 4096 x 1413 sheet. Only composites on screen are loaded.
- **Duplicated shared frames.** A frame used by several composites is stored in each of their sheets. This keeps one pack per composite and costs little.
