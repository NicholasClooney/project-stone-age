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

## Pet thumbnails stay RGBA

宠物大全's thumbnails (`thumbs/atlas-*.png`, `tools/build_pet_thumbs.py`, 4.5 M pixels, 18 MB as RGBA when every atlas is loaded) are not palette textures, because they cannot be drawn byte-identically from one:

- The 67 sprites larger than 128 px are downscaled with Lanczos, which makes new colours and partial alpha (up to 154,000 colours in one atlas). The other 622 keep their original pixels and would fit the palette all battle sheets share (223 colours).
- The grid draws them scaled into 104x86 cells with linear filtering: the window sits under the UI `CanvasLayer`, so it takes the project's default filter, not the field's nearest. The shader picks one texel (it must, since blending indices is meaningless), so even the 622 exact ones would look sharper than today, and emulating bilinear filtering in the shader would not match the GPU's own filtering byte for byte.

Options if the memory matters more than that look: unscaled thumbnails in palette atlases drawn nearest, the scaled ones in an RGBA atlas (about 18 to 7 MB with everything loaded; a visible change to the grid), or downscale with nearest at import so all of them fit (a larger visible change).

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
