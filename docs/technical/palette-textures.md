# Palette textures

The original art is 8-bit palette art, and the importers already save every sprite sheet as a lossless 256-colour PNG ([sprite sheets](sprite-sheets.md#lossless-256-colour-sheets)). Godot's importer expands each one to RGBA8, so on the GPU a sheet costs four bytes a pixel: a battle sheet averages 10.6 MB and the largest is 67 MB. On a phone (WebGL, no VRAM compression for this art) that is most of the page's texture memory.

`client/scripts/palette_sheet.gd` keeps a sheet at one byte a pixel instead and decodes the colours in a shader.

## Format

A palette sheet is drawn from two textures:

- **Indices**: the PNG's palette indices as a `FORMAT_R8` texture, exactly the sheet's size. `AtlasTexture` frames of it use the same rectangles as before.
- **Palette**: the sheet's 256 colours as a 256x1 RGBA8 texture (1 KB), from the PNG's `PLTE` (colours) and `tRNS` (alpha; entries past its end are opaque), the way libpng expands the image.

The index texture's meta `palette_material` is the sheet's `ShaderMaterial`: the shared shader with that palette. The shader samples `TEXTURE` at `UV` like the default shader does, so the GPU's nearest sampling picks the same texel it picks in the RGBA sheet at any position, scale or flip, and then looks the colour up with `texelFetch`. `COLOR` in `fragment()` is already the texture sample times the vertex colour, so the shader carries the vertex colour (the node's modulate) over from `vertex()` itself.

`PaletteSheet.apply(node, texture)` gives a node its sheet's material while it shows a palette texture and takes it away for any other texture. A node drawing palette sheets must sample nearest, as every sprite node does: linear filtering would blend indices, not colours.

Decoding needs no extra files and no GDScript pixel loop: the pixel data of an 8-bit palette PNG is the same bytes as a greyscale PNG of its indices, so `decode()` rewrites the header to greyscale, drops `PLTE` and `tRNS`, and lets Godot's PNG decoder read the indices.

## Setting

Project setting `stone_age/rendering/palette_sheets` lists the kinds of art drawn from palette sheets (`PaletteSheet.KINDS`: `battle`, `riding`, `characters`, `tiles`). Empty or missing means everything is drawn from Godot's imported RGBA textures, as before.

For a listed kind:

- the game loads the sheet PNG itself (`PaletteSheet.load_texture`) instead of the imported texture;
- `client/tools/build_web_packs.gd` ships the sheet's PNG as it is, without the `.import` remap and the imported RGBA copy, so the web build downloads the palette PNG and reads it with `FileAccess`. It does so only for a file that is an 8-bit palette PNG (`PaletteSheet.ships_png` reads the header): an image not converted yet keeps its imported copy and is drawn as RGBA.

Materials are cached by palette (`material_for`), so sheets with the same palette share one material. That is what lets one node draw many map tiles.

## Map tiles (`tools/palette_images.py`)

Map tiles and props are single PNGs in `images/` (along with the walking frames maps draw), not sheets, and the ground draws hundreds of them on one node (`legacy_ground.gd` `_draw`), which can have only one material. They fit one palette: all 5,091 images use 238 opaque colours, with no partial alpha. `tools/palette_images.py` (last in `scripts/setup-original-data.sh`, after the importers that write `images/`) rewrites every image as an 8-bit PNG with that shared palette, losslessly: index 0 is transparent (a key colour no image uses), the colours follow sorted. An image with partial alpha or a colour that does not fit stays RGBA, and so does everything if the folder ever needs more than 255 colours. Images that already have the palette are not rewritten, so web packs stay cached. Re-run it after any importer that writes `images/`; until then new images are drawn as RGBA.

- `game.texture(ident)` and the walking frames maps draw (`legacy_actor.gd`, `game.character_frame`) load through `PaletteSheet.load_any`.
- `legacy_ground.gd` gives itself the shared tile material and draws the palette tiles; any tile that is not one (not converted, or the player's switch is off) goes to a child node without the material (`plain`). `legacy_props.gd` gives each prop sprite its material.
- The player's switch also empties `game.textures` and redraws the ground at once.

## Pet thumbnails: separate palette and original RGBA variants

宠物大全 now shares the device's **调色板贴图（省显存）** switch. This is
an intentional visual tradeoff, rather than a claim that nearest looks like
Lanczos/linear. The original 689 standing-frame thumbnails remain in
`thumbs/atlas-*.png`: their pixels, layout and existing PNG bytes are unchanged.
An unchanged atlas is kept rather than re-encoded, since Pillow/zlib versions
can produce different PNG bytes from identical pixels.

`tools/build_pet_thumbs.py` also writes five `thumbs/palette-*.png` atlases.
It reads the union of the battle sheets' original opaque PLTE colours (223
colours in the current import), uses one shared 256-entry palette with index
zero transparent, and uses exact index lookup without colour quantization.
Frames larger than 128 px are resized nearest; dimensions, frame selection,
source crop and the atlas rectangles are the same as the original variant.
Alpha is always 0 or 255; hidden RGB of transparent texels is immaterial.
The original variant keeps Lanczos, including its new colours and partial alpha.
`thumbs/index.json` retains `files` and `sprites` and adds `palette_files`, whose
file indices align with `files`.

`PetThumbnails` chooses the variant, caches one texture per atlas, and applies
the shared shader to every grid/list/detail `TextureRect`. Each picture node
explicitly samples **nearest when palette**, **linear when RGBA**, even under
the UI CanvasLayer. The public setting clears both frame and atlas caches and
releases every old picture/material reference immediately, including hidden
variants. Detail pictures retry after a web pack arrives. Older imports without
pre-cut atlases still cut a standing frame locally, selecting nearest indexed
source art on and original Lanczos RGBA off.

Both variants belong to independent `thumbs-*` packs (`thumbs-0` versus
`thumbs-palette-0`, etc.); the index stays in core. Startup and setting changes
prefetch only the currently selected variant. Palette packs contain raw PNGs
without an imported RGBA remap; original packs keep the original import.
Already mounted packs remain mounted for the web session (Godot cannot unmount
them), but switching releases the old variant's GPU atlas references.
This path reads no backend and works on remote clients as well.

### Thumbnail GPU verification and measurements

```sh
.tools/asset-venv/bin/python tools/build_pet_thumbs.py
./scripts/run.sh --headless --editor --import --quit
.tools/asset-venv/bin/python tools/palette_web_check.py --thumbs --gpu \
  --modules <scratch-with-playwright-core> --chrome <full-Chrome-for-Testing>
```

The checker exports a dedicated real web project, serves it on a random port,
and runs headless Chromium without opening windows. On 2026-10-01 Chrome for
Testing / Godot 4.6 / WebGL 2 reported **ANGLE Metal Renderer: Apple M4 Max**,
not SwiftShader. All five entire atlas viewports were GPU byte-exact to RGBA
nearest references independently rebuilt from the original standing frames.
All 689 actual 104×86 `TextureRect` cells under a CanvasLayer were also
byte-exact to those nearest references. Off was byte-exact for all 689 cells
to an independently imported original Lanczos atlas drawn linear. These are
separate baselines; nearest was never compared to Lanczos as if identical.

The checker intercepts real WebGL `texImage2D` / `texStorage2D` and
`deleteTexture` calls, counts known formats and rejects unrecognized formats.
After loading **all five atlases** together:

| Mode | Observed WebGL live allocation bytes | Godot `RENDER_TEXTURE_MEM_USED` delta bytes |
| --- | ---: | ---: |
| Off, original RGBA atlases | 19,509,248 | 26,005,548 |
| On, R8 atlases + newly allocated shared palette | 4,878,336 | 6,503,431 |

Observed WebGL allocation reduction: **14,630,912 bytes (about 75%)**. On uses
4,877,312 bytes for the five R8 atlases and one 1,024-byte shared palette. The
OFF → ON → OFF measurement freed every atlas allocation before loading the
next variant. Only the shared 1,024-byte material palette can remain cached.
Godot's monitor reports a larger allocation total in this web renderer; it is
recorded separately and is not substituted for the WebGL calls.

These are instrumented API texture allocations, **not physical GPU residency**
or whole-game/browser process memory. The dedicated export loads all thumbnail
atlases but excludes the live map, battle, font and network session. Headless
Godot tests validate cache ownership, raw PNG packs, local fallback and the
real encyclopedia UI switch; they cannot validate rendered pixels. Real web
pixel/allocator checks validate the thumbnail drawing components, not an
interactive screenshot of the user's live game.

## Player switch

设置 → 画面 → **调色板贴图（省显存）** (`SettingsPaletteTextures`, on by default) is saved per device in `viewer.cfg` (`palette_textures`) and read by `game_device.gd` when the device settings are restored. Off sets `PaletteSheet.user_on = false`: `PaletteSheet.load_any` then gives the imported RGBA texture, or, on the web, where a pack of an enabled kind holds only the PNG, an RGBA texture decoded from that PNG (`load_rgba`), so a sheet is always drawn. The switch applies live: it empties `SheetFrames` and the frames of every cached sprite entry, and each sprite on screen takes the new kind of texture at its next frame (`apply` removes the material for an RGBA frame). On the web `window.stoneAgeDev("palette_on")` / `("palette_off")` flip it from the console.

## Where it is on

| Kind | On since | Drawn by |
| --- | --- | --- |
| `battle` | battle sprites commit | `battle_view.gd` actors (mounted actors draw riding sheets, which follow `riding`), `pet_follower.gd`, `animated_portrait.gd`, `adventure_menu.gd` portraits |
| `riding` | riding and field characters commit | `legacy_actor.gd` mounted (field), `battle_view.gd` mounted actors |
| `characters` | riding and field characters commit | `legacy_actor.gd` walking frames from `game.character_frame` (the player, other players, the character chooser's previews when they use sheets) |
| `tiles` | map tiles commit | `legacy_ground.gd` (one material for the layer), `legacy_props.gd`, `legacy_actor.gd` frames from `images/` |

Every node that shows a `SpriteArt.texture` frame calls `PaletteSheet.apply` after setting it. Code that only needs to know a sheet is here uses `PaletteSheet.exists(path)` (`BattleArt.renderable`, 宠物大全), and code that reads a sheet's pixels on the CPU uses `PaletteSheet.picture(path)` (thumbnails without a pre-cut atlas): on the web an enabled kind's pack holds only the PNG, so `ResourceLoader.exists` and `load()` would not find it.

## Tests

- `client/tests/settings_menu_test.gd`: the switch is on by default, off draws the player's next frame from an RGBA sheet without the material and the ground from RGBA tiles at once, the choice is saved and restored, and on draws palette textures again.
- `client/tests/mvp_journey_test.gd`: battle actors, the following pet, the walking player, the ground and props use their palette material.
- `tools/test_palette_images.py`: images share one palette and keep every visible pixel; re-runs leave them alone; partial alpha stays RGBA; more than 255 colours keeps everything RGBA.
- `client/tests/pet_thumbnail_palette_test.gd`: all frame bounds and shared palettes, all on/off paths and shader flags, explicit node filters, real encyclopedia/device toggle, released old atlas references, raw mounted PNG packs, local fallback and UI without a backend.
- `tools/test_build_pet_thumbs.py`: all 689 independent nearest frame references, exact shared original colours and binary alpha, old PNG byte preservation, unchanged Lanczos/layout; `tools/test_plan_web_packs.py`: both variants have complete independent thumbnail pack ownership.
- `client/tests/palette_sheet_test.gd` (headless suite): indices plus palette reproduce Godot's own RGBA decode of sample sheets of every kind byte for byte, and the imported texture's visible pixels (`fix_alpha_border` recolours hidden ones); the texture and material layout; `apply`; the setting being off by default. It also prints the expected texture memory of every sheet.
- `tools/palette_web_check.py`: the shader on a real GPU without opening a window. It builds a small web export holding `palette_sheet.gd`, `client/tests/perf/palette_render_check.gd` and sample sheets, and runs it in headless Chromium (WebGL 2, the renderer phones and Vision Pro use). Each sheet is drawn as RGBA and through the shader in 24 views (plain, modulated, flipped, scaled by 2, 1.37 and 0.75, at a fractional position, as a scaled `TextureRect`, and as the field draws an actor: a sprite inheriting nearest filtering from its actor under a `Camera2D` zoomed to 1, 0.5, 0.73 and 1.6 in a viewport with the project's linear default; at both ends of the sheet) and the pixels read back must be equal byte for byte. `--gpu` runs it on the Mac's GPU through ANGLE on Metal, the way Safari (Mac, iPhone, Vision Pro) draws WebGL, instead of SwiftShader; it prints the WebGL renderer it got.

```sh
npm install --prefix <scratch> playwright-core
python3 tools/palette_web_check.py --modules <scratch> \
  --chrome ~/Library/Caches/ms-playwright/chromium_headless_shell-<rev>/chrome-headless-shell-mac-arm64/chrome-headless-shell
# On the real GPU (needs the full Chrome for Testing, not the headless shell):
python3 tools/palette_web_check.py --gpu --modules <scratch> \
  --chrome ~/Library/Caches/ms-playwright/chromium-<rev>/chrome-mac-arm64/'Google Chrome for Testing.app'/Contents/MacOS/'Google Chrome for Testing' \
  client/assets/legacy/riding/sheets/101317.png
```

Checked against a report that a rider looked worse (character 100030 on 扬奇洛斯, composite 101317, a lossless 214-colour sheet): byte-identical in all 24 views on SwiftShader and on an Apple M4 Max through ANGLE Metal, and in the running web client with that save, switch on against switch off (screenshots of the rider, 0 pixels differ). The solid black shadow under that mount is in the RGBA sheet as well.

## Measured

Texture memory of all sheets as RGBA and as palette sheets (`palette_sheet_test.gd`):

| Kind | Sheets | RGBA | Palette | Average | Largest |
| --- | --- | --- | --- | --- | --- |
| Battle | 643 | 6,832 MB | 1,709 MB | 10.6 to 2.7 MB | 66.7 MB |
| Riding | 241 | 4,099 MB | 1,025 MB | 17.0 to 4.3 MB | 24.2 MB |
| Characters | 47 | 82 MB | 21 MB | 1.7 to 0.4 MB | 2.9 MB |

WebGL 2 in headless Chromium, `RENDER_TEXTURE_MEM_USED` for one 4091x1213 riding sheet: 25.2 MB as RGBA, 6.3 MB as a palette sheet.

The web build in headless Chromium (`window.stoneAge.texture_mb`, which `tools/web_memory_probe.mjs` now prints), Samgir wilderness (map 100) then a battle: texture memory grew 9.9 MB opening the battle with RGBA battle sheets and 2.9 MB with palette sheets. `window.stoneAge.texture_kinds` (MB of live textures by kind, from `perf_registry.gd`) on fresh saves, all three kinds off and then on: the player's character sheet in Samgir 1.3 to 0.3 MB; battle sheets after one battle 8.9 to 3.6 MB (a different encounter each run, so only roughly comparable). With tiles on as well: the map's tiles 16.9 to 4.2 MB in Samgir and 20.2 to 5.0 MB in the wilderness (map 100); all textures in the wilderness 42.0 MB with every kind off, 20.6 MB with every kind on. Loading 1,500 tiles takes about the same time either way (desktop, headless: 199 to 295 ms as palette textures, 270 to 682 ms imported). Tile packs stay about the same size (17.6 MB of palette PNGs instead of 16.7 MB of imported copies).

Shipping battle sheets as their PNGs also shrinks their packs: 368 MB of PNGs instead of 454 MB of imported RGBA copies across all 643 sheets.
