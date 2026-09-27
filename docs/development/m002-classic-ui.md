# M002 — Original menus and map window

Hover at the bottom edge to reveal Map, Status, Pet, Item, Mail, Album, and System using the original textured tabs. The original stone top panels and green buttons show hover labels. Only Map is wired to gameplay; other classic buttons are visual. Existing preview controls occupy a separate DEV row.

Click Map or press Ctrl+M to toggle the original map window. Its original close button and Escape close it. Drag the title to reposition it. The live map follows the player, shows east/south coordinates, and flashes the center marker. Walking continues while it is open; clicks within the panel do not move the player.

**Max out** fits and centers the entire village. Normal zoom restores player follow. Tile culling uses the actual camera and zoom, so the full map remains rendered at overview scale.

## Asset evidence and limits

`tools/import_ui.py` imports 38 PNGs and terrain colors from the same local client as M000. Outputs remain in ignored `client/assets/legacy/ui/`; run after the main map import.

Original logical graphic IDs must resolve through ADRN's `attr.bmpnumber` field at offset 76. They are not direct archive frame indexes. This also corrects the previous NPC importer: logical 16039 maps to archive bitmap 5885.

Client source reference: [anson1788/stoneage, revision 1997fc2](https://github.com/anson1788/stoneage/tree/1997fc20456dbda36d181b9680ae10bed2e9cdf9), under `石器时代8.5客户端最新源代码/石器源码`:

- `systeminc/anim_tbl.h`: task-bar background 26012; task tabs 26150–26163; close button 26042; top-frame and button IDs.
- `system/loadrealbin.cpp`: `bitmapnumbertable[attr.bmpnumber] = bitmapno` establishes logical-ID mapping.
- `system/menu.cpp`: bottom-edge hover reveal; map window size 248×240, name at (22,31), coordinates near (61,186), close button at (124,222).
- The local archive resolves map frame 26081 to bitmap 9200. Frame and labels were visually inspected.
- `system/map.cpp`: 54×54 local automap area centered on the player and object footprints.
- `system/directdraw.cpp`: average opaque sprite pixels, nearest original palette entry, 4×2 automap cells, blinking player marker.

The supplied screenshot has additional top-row features not present in this local asset set. This slice uses the verified 2.5 artwork, not screenshot crops or invented replacement icons. The top time indicator is static. Text uses bundled Noto Sans SC. The minimap shows local imported terrain without historical exploration fog or server discovery state. UI scale is 1.25; the wooden footer stretches to the viewport width.

## Verification

Run `./scripts/test.sh` for movement, NPC, and UI suites. UI tests cover hover reveal/retract, visual-only controls consuming clicks, map open/close, Ctrl+M without muting, live coordinates, map click isolation, overview camera centering, terrain coverage, and returning to player follow. NPC regression verifies corrected bitmap mapping. All three suites and the 10 binary-decoder tests passed; the original map panel and complete-village view were rendered and inspected. Noto Sans SC needs numeric OpenType axis tag `2003265652` for its weight; string `wght` leaves this font at its thin default.

Run `./scripts/run.sh --script res://tests/ui_capture.gd` for deterministic screenshots in `artifacts/`; this test exits. Desktop pointer events can interfere with injected hover in a visible test window, so interaction tests run headless and the capture harness sets explicit visual states. Launch normal play with `./scripts/run.sh`.

Earlier tested slices remain separate commits: `ad89b51` (village) and `049fe7d` (NPC). This slice adds a new conventional commit without rewriting them.
