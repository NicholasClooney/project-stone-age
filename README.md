# Project Stone Age

A playable **Godot 4.6** exploration slice of **萨姆吉尔村 / Samgir**, using the legacy game's map, sprites, palettes, animation frames, and music.

## Play

On this Mac, double-click **Play Stone Age.command**, or run from the repository root:

```sh
./scripts/run.sh
```

The project-local Godot runtime is already installed under `.tools/`. You can also open `client/project.godot` in Godot 4.6 and press F6/F5 as appropriate. For another installation, set `GODOT_BIN` to the Godot executable.

| Control | Action |
| --- | --- |
| Left click | Walk to a reachable tile; click the villager to approach and talk |
| Villager button | Walk to the resident at (93, 72) and talk |
| Enter / Escape during dialogue | Close the conversation |
| WASD / arrows | Walk in screen directions; combine keys for eight directions |
| E | Original waving animation |
| X | Sit / stand |
| Tab | Cycle three original character appearances |
| Mouse wheel / + / − | Zoom from 40% to 200%, in shared 10% steps |
| Max out (DEV controls) | Set the same zoom to its 40% minimum; keep following the player |
| Hover bottom edge | Reveal the original seven menu tabs |
| Map tab / Ctrl+M | Toggle the original map window; drag its title to move it |
| M | Mute / unmute |
| H / Escape | Open / close help; music volume is in help |
| R | Return to the village square |

Normal play stays open until you close the window. `client/tests/capture.gd` is an automated screenshot test that exits; it is **not** the player launcher.

## What works

- Original 160 × 160 Samgir map, 482 scenery objects, original isometric projection and depth sorting.
- 1,066 decoded original textures; three characters with original eight-direction idle/walk frames, sit, and wave.
- Original map/ADRN collision footprints, keyboard movement, and click-to-walk with corner checks.
- Original `sabgm_t0.wav` village BGM, loop and volume controls, and a legacy UI sound.
- One original village resident at (93, 72), with the recorded sprite and first dialogue line, original stone-frame art, confirmation button, and open/close sound effects.
- Original stone top controls, wooden hover-reveal bottom menus, and a working original map window with live coordinates and player marker.
- Camera follow, consistent developer zoom controls, focus-loss input clearing, and a safe respawn.

This is the local, Godot-only village slice. No login, separate gameplay authority, battle, interior transitions, saves, or multiplayer yet. The classic HUD uses the local 2.5 client artwork. Extra top-row buttons in the supplied reference belong to a different asset set and are not fabricated. Only the Map tab is functional; the other original menu items are visual with hover labels. DEV controls remain separate. Movement timing is a local implementation; complete historical gameplay parity is not claimed.

The rejected geometric placeholder demo is not the default or part of the tracked game. It was moved into an ignored local research folder.

## Original resources

The imported resources are present locally in `client/assets/legacy/` and deliberately excluded from Git. The importer and provenance documentation are tracked. A fresh clone needs a compatible local resource import before playing; the game explains this if assets are absent.

The current input is the community-distributed **SA2.5-20260823** client from [99ds.com](https://99ds.com/), with Samgir geometry from [chenmingbiao/stone-age](https://github.com/chenmingbiao/stone-age/tree/master/gmsv/data/map/sainasu/samugiru). This preserves the original village layout instead of later decorative additions in that client cache. The exact official release lineage is unverified.

```sh
python3 -m venv .tools/asset-venv
.tools/asset-venv/bin/pip install -r tools/requirements.txt
.tools/asset-venv/bin/python tools/import_legacy.py /path/to/stoneage2.5 \
  --server-map /path/to/samugiru
.tools/asset-venv/bin/python tools/import_ui.py /path/to/stoneage2.5
./scripts/run.sh --headless --editor --import --quit
./scripts/run.sh
```

The client directory must contain `data/adrn_15.bin`, `real_15.bin`, `spradrn_5.bin`, `spr_4.bin`, `pal/Palet_1.sap`, the audio files, and `map/1000.DAT`. The optional `--server-map` reads a matching `LS2MAP` Samgir file. Without it, the client DAT is used and unresolved decorations are recorded, not silently replaced with invented art.

To import the resident, obtain `poru/samugiru01.create` and `poru/samugiru02` from the [pinned legacy NPC source](https://github.com/chenmingbiao/stone-age/tree/0c58fb6683a49a178a8ad845a8c296c2cb83bd81/gmsv/data/npc) into a local directory, preserving `poru/`, then run:

```sh
.tools/asset-venv/bin/python tools/import_npc.py /path/to/stoneage2.5 /path/to/npc
./scripts/run.sh --headless --editor --import --quit
```

The importer reads the original position, fixed graphic, name, and first comma-separated dialogue entry without rewriting the Chinese. Generated files remain ignored. Missing NPC content leaves exploration available and the Villager button explains the missing import. See [the NPC slice](docs/development/m001-village-npc.md) for evidence and limitations.

See [resource evidence](docs/reverse-engineering/samgir-import.md) for hashes, format decisions, and limitations. Do not add imported client archives or assets to a public release without resolving their distribution status. The bundled Noto Sans SC font is distributed under its included OFL license.

## Local reference sources

Full upstream checkouts and offline Git bundles are preserved in ignored `references/`. See [local reference archives](docs/reverse-engineering/local-references.md) for paths, checksums, and recovery instructions.

## Verify

```sh
./scripts/test.sh
.tools/asset-venv/bin/python -m unittest discover -s tools -p 'test_*.py'
```

The UI suite checks menu hover, click isolation, map toggles/live coordinates, shared zoom limits, and original open/close UI sounds. See [classic UI evidence](docs/development/m002-classic-ui.md). The NPC suite checks approach, collision, cancellation, dialogue input, closing, and resumed exploration. The Godot movement suite exercises actual movement, original direction mapping, collision, pathfinding, 200 repeated movement steps, animation, character switching, and audio looping. It needs imported assets. [Verification notes](docs/development/m000-status.md) distinguish automated checks from visual inspection.

## Layout

- `client/` — Godot scene, local simulation, renderer, and tests.
- `tools/import_legacy.py` — bounded binary decoder and deterministic conversion.
- `scripts/` — launch and test helpers.
- `docs/` — [design specification](docs/README.md) and implementation notes.
- `.tools/`, `artifacts/` — ignored local engine, source references, and verification output.
