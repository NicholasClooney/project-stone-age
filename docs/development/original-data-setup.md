# Original data setup

`./scripts/setup-original-data.sh` takes a fresh clone to a playable game. This page explains what it fetches, how to do the same by hand, and what to watch for. Everything it creates is gitignored.

## What the script does

| Step | Result | Source |
| --- | --- | --- |
| Godot 4.6 | `.tools/Godot.app` (macOS; elsewhere install `godot` or set `GODOT_BIN`) | [Godot 4.6-stable release](https://github.com/godotengine/godot/releases/tag/4.6-stable) |
| Web export templates (`--web`) | `web_*` templates in Godot's export template folder | same release, `Godot_v4.6-stable_export_templates.tpz` |
| Python tools | `.tools/asset-venv` with Pillow (`tools/requirements.txt`) | PyPI |
| Reference repositories | `references/chenmingbiao-stone-age` (server data, maps, NPC scripts, `char_base.c`) and `references/anson1788-stoneage` (client source, cursor) at the pinned revisions | GitHub, or the offline bundles in `references/archives/` when present ([local references](../reverse-engineering/local-references.md)) |
| StoneAge 2.5 client | `.tools/legacy/client25.rar` extracted to `.tools/legacy/extracted/SA2.5-20260823/` | [99ds.com](https://99ds.com/) `downloads/windows/Stoneage2.5-Windows.rar` |
| StoneAge 8.0 data (`--with-8.0`) | `.tools/legacy/Stoneage8.0-Windows.zip`, only its `data/` folder extracted to `.tools/legacy/extracted/SA8.0-20260803/` | 99ds.com `downloads/windows/Stoneage8.0-Windows.zip` |
| Imports | `client/assets/legacy/` | all importers, in order (below) |
| Godot import | `client/.godot/imported/` | `./scripts/run.sh --headless --editor --import --quit` |

Recorded checksums (SHA-256). A mismatch is reported as a warning: the upload changed, and imports may differ from the documented ones.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Stoneage2.5-Windows.rar` (`client25.rar`) | 553,320,338 | `0e157c0fcfe2bcf91826907d580d4403138d86fab9488aa39cd9494af17449ae` |
| `Stoneage8.0-Windows.zip` | 1,214,843,601 | `48bef440851d361d699358ab70ffbd38f6b92c6263fb243863987fb54998475e` |

Both archives also contain Windows executables and libraries. The script excludes them when extracting and never runs anything it downloads. Do not run them.

The 8.0 data contains graphics the 2.5 client lacks (for example the per-appearance mounted sprites of the later certificate ride pets, 101305 to 101400 and 1019xx, and map graphic 22413). The importers read the 2.5 files; using the 8.0 set is work in progress.

## Timing

Downloads are about 550 MB (1.8 GB with `--with-8.0`). The importers take a few minutes; Godot's first asset import of the roughly 100,000 extracted images takes most of the time. A test from a fresh clone (Godot, references and imports, the 2.5 archive already present) took 37 minutes on an M-series Mac, after which all test suites passed. Later runs skip finished steps; `--import-only` re-runs just the importers and Godot import.

## Doing it by hand

With the client at `$CLIENT` (the folder containing `data/`, `map/` and the audio) and the references cloned:

```sh
python3 -m venv .tools/asset-venv
.tools/asset-venv/bin/pip install -r tools/requirements.txt
SERVER=references/chenmingbiao-stone-age/gmsv
PY=.tools/asset-venv/bin/python
$PY tools/import_legacy.py "$CLIENT" --server-map $SERVER/data/map/sainasu/samugiru/samugiru
$PY tools/import_ui.py "$CLIENT"
$PY tools/import_npc.py "$CLIENT" $SERVER/data/npc
$PY tools/import_wilderness.py "$CLIENT" --server-map $SERVER/data/map/sainasu/sainasu
$PY tools/import_battle.py "$CLIENT"
$PY tools/import_battle_backgrounds.py "$CLIENT"
$PY tools/import_mvp.py "$CLIENT"
$PY tools/import_world.py "$CLIENT"          # also runs the Dana NPC import
$PY tools/import_pet_training.py "$CLIENT"
$PY tools/import_characters.py "$CLIENT"
$PY tools/import_pets.py "$CLIENT"
$PY tools/import_mirror.py "$CLIENT"
$PY tools/import_loading.py "$CLIENT"        # web waiting screen; uses ffmpeg if present
$PY tools/import_riding.py "$CLIENT"         # after characters: riders are checked against them
$PY tools/import_grid_cursor.py "$CLIENT"
$PY tools/import_cursor.py 'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/123.cur'
python3 tools/import_encounters.py
$PY tools/import_encounter_art.py "$CLIENT"
./scripts/run.sh --headless --editor --import --quit
```

The client folder must contain `data/adrn_15.bin`, `real_15.bin`, `spradrn_5.bin`, `spr_4.bin`, `pal/Palet_1.sap`, the audio files and `map/1000.DAT`. `--server-map` reads the original Samgir layout from the server data instead of the client cache's later decorations; unresolved decorations are recorded, never replaced with invented art. See [resource evidence](../reverse-engineering/samgir-import.md) for formats and hashes.

After re-importing maps or encounters, regenerate the tracked spot indexes: `python3 tools/build_training_spots.py` and `python3 tools/build_level_one_spots.py`.

## Decoding notes

Graphics use the original RLE format. Some original bitmaps' last run is one pixel longer than the image; the original client (`unpack.cpp`, `decoder()`) writes runs without a bound and keeps the first `width × height` bytes, so the importer clips the same way. This recovers six character appearances, the gold-tiger rider variant 101076 and the monster 凯比特 (100298). Appearance 100100 stays unavailable: its club sprite points at bitmap 4294967295 in every known client.
