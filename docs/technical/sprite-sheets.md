# Sprite sheets

The original client stores every animation frame as its own bitmap. Importing them one PNG per frame made the Godot project hold well over 100,000 tiny files. The importers now pack the frames of one animated thing (a rider and mount composite, a battle sprite, a player character) into one sprite sheet, and the game cuts frames out of it.

| Art | Sheet per | Packed by | Manifest | Sheets |
| --- | --- | --- | --- | --- |
| Riding | rider and mount composite | `tools/import_riding.py` | `riding/manifest.json` | `riding/sheets/` |
| Battle sprites | battle sprite (player, pet, enemy) | `tools/pack_frame_sheets.py battle` | `battle/manifest.json` | `battle/sheets/` |
| Walking art | player character | `tools/pack_frame_sheets.py characters` | `characters/catalog.json` | `characters/sheets/` |
| Map tiles and props | not packed, see below | | map JSON | `images/` |

## Why per-frame PNGs were slow

Every PNG under `client/` costs far more than its pixels:

- **Godot import.** Each file gets its own `.import` file, uid and compressed `.ctex`, and is processed on its own. With the 8.0 riding data (69,952 frames) the first import took about 40 minutes.
- **Web packs.** A `riding-<id>` pack held a few hundred small files, which made building and downloading packs slow.
- **Runtime.** Every frame was a separate texture load the first time it was drawn.

## Packing (`tools/sprite_sheets.py`)

`save_sheets(frames, folder, stem)` packs, converts and saves one sheet (or `stem-0.png`, `stem-1.png` when it needs several) and returns the manifest entry. All sheet producers use it.

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

## Battle sprites and walking art (`tools/pack_frame_sheets.py`)

Several importers write battle frames (`import_battle`, `import_characters`, `import_pets`, `import_mirror`, `import_encounter_art`) and one writes walking frames (`import_characters`). They still write one PNG per frame and register it in their manifest's `characters` and `images`; `pack_frame_sheets.py` runs after them (last in `scripts/setup-original-data.sh`) and:

- packs each sprite's frames into `<folder>/sheets/<sprite>.png` and writes the manifest's `sheets`;
- deletes the packed PNGs and their `.import` files. The walking-art folder `images/` is shared with map tiles and props, so a frame a map JSON still names keeps its PNG (Samgir's villagers wear player character 100000's art: 336 frames stay);
- is safe to re-run after a single importer: a frame whose PNG is gone is cut back out of the existing sheet (sheets are lossless), and new sheets are written to `sheets.new` and swapped in only once every frame was read.

Importers that add battle frames recreate `battle/images` when needed, since the packer removes it once it is empty.

Pet sprites kept in `battle/pets/<sprite>.json` (the manifest's `extra_sprites`, see [8.0 pets](../reverse-engineering/pets-8.0.md)) are packed into the same `battle/sheets/` and their file gets its own `sheets`.

A battle bitmap number names one picture: 8.0 bitmaps whose number 2.5 uses for another picture are renumbered by the importer. Callers that know only the bitmap (battles) use `SheetFrames.bitmap_texture`, which builds a bitmap to sheet index per folder and rebuilds it when sheets were added (an extra sprite merged in by `BattleArt.ensure`).

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

`client/scripts/sheet_frames.gd` `texture(folder, sheets, key, bitmap)` returns an `AtlasTexture` whose atlas is the sheet and whose region is the frame's rectangle. Sheets and frames are cached in static dictionaries, so each sheet loads once and each frame object is made once. When a sheet is not available yet (its web pack is still downloading) it returns `null` and caches nothing, so the next draw tries again. Its users:

- riding: `riding.gd` `frame_texture(composite, bitmap)`, for `legacy_actor.gd` (field) and `battle_view.gd` (mounted battles);
- battle sprites: `battle_view.gd` (`bitmap_texture`), `pet_follower.gd`, `animated_portrait.gd`, `adventure_menu.gd` portraits, and `server/troop_art.gd` (`available`, to validate encounter art);
- walking art: `game.character_frame(character, bitmap)`, which falls back to the single PNG for map residents and frames that are not packed.

`sheet_frames_test.gd` checks that every frame of sample sprites comes from its sheet at the frame's size, that every sprite's first frame is found by bitmap alone, and that the per-frame PNGs are gone.

## Web packs

`tools/plan_web_packs.py` puts each sheet in the pack that already stood for its sprite: `riding-<id>`, `sprite-<id>` and `char-<id>`. Frame PNGs still present (walking frames maps also draw, or an import not packed yet) stay in those packs as before.

## Measured (M-series Mac)

| | Riding (8.0 data) | Battle sprites | Walking art |
| --- | --- | --- | --- |
| Frames | 69,952 | 42,773 | 5,264 |
| Files after | 241 sheets | 172 sheets | 47 sheets, plus 336 PNGs maps draw |
| Source size | 1.1 GB to 234 MB | 422 MB to 61 MB | 20 MB of frames to 6 MB |
| Packing | `import_riding.py` about 6 min to under 2 min | 31 s | 5 s |
| Godot import of the sheets | about 40 min to 28 s | 10 s | 4 s |
| Web packs | 372 MB, 1.5 MB average, 2.9 MB largest | 140 MB to 96 MB (0.82 to 0.56 MB average, 2.2 MB largest) | 16 MB to 11 MB (0.24 MB average) |

Source sizes count what is on disk, `.import` files included. The Godot project went from about 123,000 imported PNGs to about 5,200, of which 4,270 are map tiles and props. The core web pack also shrank from 38 MB to 30 MB. Building all 1,387 web packs from scratch takes about 7 seconds.

## Map tiles and props are not packed

The remaining 4,270 PNGs in `images/` are ground tiles and props, and they were left as single files on purpose:

- **Little to gain.** At the riding import's rate (about 34 ms per file) they cost Godot about 2.5 minutes of first import, against the 40 minutes the frames cost. Their web packs are already grouped: 530 `tiles-<hash>` packs (15 MB, 30 KB average) by the exact set of maps that use them, plus map-only tiles in `map-<id>`.
- **Coupling.** A tile's sheet would have to follow `plan_web_packs.py`'s grouping by map set, so the importer would depend on the planner and a new map would repack sheets for other maps.
- **Map switching.** `legacy_ground.gd` and `legacy_props.gd` draw tiles through `game.texture(ident)`, a lazy cache that loads only the tiles in view. The map-switch work (0.64 s to 0.085 s in Samgir) relies on that; loading whole sheets per tile group would read tiles that are not on screen.

Worth revisiting only if the tile count grows a lot (for example many more maps from the 8.0 data).

## Trade-offs

- **The palette is lost in the build.** Godot imports the sheet as a full-colour lossless texture, so the web packs (355 MB) are larger than the palette PNGs (234 MB). Keeping palette data in the build would need a custom texture format and shader; not worth it yet.
- **Video memory.** A loaded sheet occupies its full size, up to about 23 MB for a 4096 x 1413 sheet. Only composites on screen are loaded.
- **Duplicated shared frames.** A frame used by several riding composites is stored in each of their sheets. This keeps one pack per composite and costs little. Battle sprites share no frames.
- **Two walking-art copies.** A player-character frame a map also draws exists both in the character's sheet and as a PNG (336 frames, about 1.3 MB).
