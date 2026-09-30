# Original data setup

`./scripts/setup-original-data.sh` takes a fresh clone to everything a working checkout has: the desktop game, the 8.0 pet art and mounts, the pet hunt helper, Godot's asset import and the web client. This page explains what it fetches, how to do the same by hand, and what to watch for. Everything it creates is gitignored. It runs on macOS, Linux, [WSL2 and Git Bash on Windows](#windows).

## What the script does

Before downloading anything it prints each download with its size, what is already there, the disk space everything takes afterwards and the free space, then asks. `--yes` skips the question, `--dry-run` only prints. Rerun it after an interruption: finished steps are skipped, downloads continue where they stopped and are checked by size and SHA-256, and archives are extracted into a staging folder that is moved into place only when complete.

| Step | Result | Source |
| --- | --- | --- |
| Godot 4.6 | `.tools/Godot.app` on macOS; `.tools/godot/` on Linux, WSL2 and Windows (the `_console.exe` on Windows). `GODOT_BIN` or `godot` on PATH are used instead when present | [Godot 4.6-stable release](https://github.com/godotengine/godot/releases/tag/4.6-stable) |
| Web export templates | `web_*` templates in Godot's export template folder. Only these four files (39 MB) are read out of the 1.25 GB template archive with HTTP range requests (`tools/fetch_zip_members.py`) | same release, `Godot_v4.6-stable_export_templates.tpz` |
| Python tools | `.tools/asset-venv` with Pillow and soundfile (`tools/requirements.txt`) | PyPI |
| Reference repositories | `references/chenmingbiao-stone-age` (server data, maps, NPC scripts, `char_base.c`) and `references/anson1788-stoneage` (client source, cursor, sound table) at the pinned revisions | GitHub, or the offline bundles in `references/archives/` when present ([local references](../reverse-engineering/local-references.md)) |
| StoneAge 2.5 client | `.tools/legacy/client25.rar`; its game folder extracted to `.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5/` | [99ds.com](https://99ds.com/) `downloads/windows/Stoneage2.5-Windows.rar` |
| StoneAge 8.0 data | `.tools/legacy/Stoneage8.0-Windows.zip`, only its `data/` folder extracted to `.tools/legacy/extracted/SA8.0-20260803/` | 99ds.com `downloads/windows/Stoneage8.0-Windows.zip` |
| Imports | `client/assets/legacy/`; redone only when an importer changed (stamp in `.tools/setup-import.stamp`) | all importers, in order (below) |
| 本机极速模式 helper | `build/fast_hunt` (`fast_hunt.exe` on Windows); skipped with a note without a C compiler | `scripts/build-fast-hunt.sh` |
| Godot import | `client/.godot/imported/` | `./scripts/run.sh --headless --editor --import --quit` |
| Web client | `build/web/` | `./scripts/build-web.sh` |

Options: `--no-8.0` skips the 8.0 data (313 pet battle sprites, the later certificate mounts and the radio's two extra tracks are then missing), `--no-web` skips the web templates and build, `--import-only` downloads nothing and redoes the imports, helper, Godot import and web build. The old `--web` and `--with-8.0` are accepted and change nothing, both are the default now.

Sizes, measured on a full checkout:

| Part | Download | On disk |
| --- | --- | --- |
| Godot 4.6 | 161 MB (macOS), 71 MB (Linux), 79 MB (Windows) | 342 MB (macOS), about 160 MB elsewhere |
| Web export templates | 39 MB | 40 MB |
| Python packages (Pillow, soundfile, numpy) | about 30 MB | 67 MB |
| Reference repositories | about 170 MB | 882 MB |
| 2.5 client | 553 MB | 553 MB archive + 1.19 GB extracted |
| 8.0 client | 1.21 GB | 1.21 GB archive + 1.82 GB data |
| Imported assets | | 861 MB |
| Godot import cache | | 916 MB |
| Web build | | 1.03 GB |
| **All** | **2.1 GB** | **about 8.9 GB** (macOS) |

The two client archives (1.77 GB) can be deleted after setup; keep them to re-extract.

Recorded checksums (SHA-256). A download with the recorded size but another hash is damaged: the script stops and asks to delete it. Another size means the upload changed: a warning, and imports may differ from the documented ones.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Stoneage2.5-Windows.rar` (`client25.rar`) | 553,320,338 | `0e157c0fcfe2bcf91826907d580d4403138d86fab9488aa39cd9494af17449ae` |
| `Stoneage8.0-Windows.zip` | 1,214,843,601 | `48bef440851d361d699358ab70ffbd38f6b92c6263fb243863987fb54998475e` |

Both archives also contain Windows executables and libraries, and the 2.5 archive a third-party bot tool (`SACH-MX0.30`). The script extracts only the game's `stoneage2.5` folder and the 8.0 `data/` folder, excludes executables, and never runs anything it downloads. Do not run them.

The 8.0 data contains graphics the 2.5 client lacks (for example the per-character mounted sprites of the later certificate ride pets, 101305 to 101400 and 1019xx, map graphic 22413, and 313 pet battle sprites). The riding import and the pet battle art import read it (`--extra-source`, below), and the radio takes its 26 tracks; every other importer reads the 2.5 files. See [original riding](../reverse-engineering/original-riding.md#certificate-mounts) and [8.0 pets](../reverse-engineering/pets-8.0.md).

## Windows

Use WSL2 or Git Bash. The scripts are POSIX shell and do not run in PowerShell or cmd; the game itself runs natively under Windows Godot either way. A PowerShell user can start them through Git Bash: `& "C:\Program Files\Git\bin\bash.exe" ./scripts/setup-original-data.sh`.

| | WSL2 (Ubuntu) | Git Bash (Git for Windows) |
| --- | --- | --- |
| Setup script | works like Linux | works |
| Godot | Linux build in `.tools/godot/`; the window opens through WSLg (Windows 11, or 10 with WSLg) | Windows console build in `.tools/godot/` |
| RAR extraction | `bsdtar` from `libarchive-tools` | Windows 10+ `tar.exe` (libarchive), or 7-Zip |
| 本机极速模式 helper | `gcc` from `build-essential` | MinGW-w64 gcc (MSYS2 `mingw-w64-ucrt-x86_64-gcc`, WinLibs or w64devkit on PATH); without it the hunt scans in GDScript |
| `serve.sh`, `build-web.sh`, `stop-server.sh` | work; open `http://localhost:8780/` in a Windows browser | work; without `lsof`, `stop-server.sh` only asks the backend to quit and cannot fall back to TERM |
| `relaunch.sh`, `profiles.sh` (Tailscale) | should work with `tailscale` in WSL or `tailscale.exe` on Windows (not tested) | should work with `tailscale` on PATH (not tested) |
| `make-cert.sh` | `sudo apt install mkcert` | `winget install FiloSottile.mkcert` |

**WSL2**, in an Ubuntu terminal:

```sh
sudo apt install curl git python3 python3-venv libarchive-tools build-essential
cd ~ && git clone <this repository> projects-stone-age && cd projects-stone-age
./scripts/setup-original-data.sh
./scripts/run.sh
```

Clone into the Linux home folder, not under `/mnt/c`: Godot's first import reads about 5,000 files, and the Windows drive is many times slower from WSL. The riding import needs about 2.5 GB of memory: if it stops with `Killed`, give WSL more (`memory=6GB` under `[wsl2]` in `%UserProfile%\.wslconfig`, then `wsl --shutdown`) and rerun. If the game window does not open, install the libraries Godot loads: `sudo apt install libgl1 libxcursor1 libxinerama1 libxrandr2 libxi6 libfontconfig1`.

**Git Bash**: install [Git for Windows](https://git-scm.com/download/win) and Python 3.10+ (`winget install Python.Python.3.12`), then in Git Bash:

```sh
git config --global core.longpaths true   # the reference repositories have deep Chinese paths
git clone <this repository> projects-stone-age && cd projects-stone-age
./scripts/setup-original-data.sh
./scripts/run.sh
```

Keep the checkout path short (for example `C:\src\projects-stone-age`). The repository's `.gitattributes` keeps LF line endings, which the shell scripts need. The scripts set `PYTHONUTF8=1` so the importers read and write UTF-8 whatever the Windows code page, find a real Python when `python3` is only the Microsoft Store placeholder, and pass Windows paths (`C:/...`) to Godot and Python. The pet hunt helper is built static (`-static -lshell32`) so Godot can start it without MinGW's DLLs on PATH.

Without a compiler the pet hunt's 本机极速模式 option is greyed out with 「本机辅助程序未编译（需要 C 编译器，运行 scripts/build-fast-hunt.sh）」 and the hunt scans in GDScript.

## Pet battle art

`import_encounter_art.py` imports the battle sprite of every pet template, not only the monsters of imported maps, so 宠物大全 shows (nearly) every species. The world's sprites and the GM special pets stay in `battle/manifest.json`; the other pets (458) each get `battle/pets/<sprite>.json`. The game reads neither: `tools/split_manifests.py` turns them into one file per sprite (`battle/sprites/<sprite>.json`, [runtime files](../technical/sprite-sheets.md#runtime-files)); the pets' files ship in their own web pack. Without the 8.0 data (`--no-8.0`), 313 sprites are reported unavailable in `encounters/art-coverage.json` and those species show 无图. `import_encounters.py` also adds 131 later album pets with art but no stats (`docs/reverse-engineering/pets-8.0.json`).

The pet art adds about 280 MB of sheets under `client/assets/legacy/battle/` (350 MB in all), about 300 MB to Godot's import cache, and 370 MB of `sprite-<id>` web packs; the web core pack grows by 0.2 MB.

To bring an existing checkout up to date, run `./scripts/setup-original-data.sh` again: it re-imports when an importer changed. By hand (8.0 data extracted):

```sh
PY=.tools/asset-venv/bin/python
python3 tools/import_encounters.py
$PY tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --extra-source .tools/legacy/extracted/SA8.0-20260803
$PY tools/import_battle_sounds.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
$PY tools/pack_frame_sheets.py battle
./scripts/run.sh --headless --editor --import --quit
```

## Timing

Downloads are 2.1 GB (about 850 MB with `--no-8.0`). The riding import peaks at about 2.4 GB of memory, so a machine or VM needs about 3 GB free. The importers take a few minutes (the riding import about two more with the 8.0 data). Riding composites, battle sprites and player walking art are packed into [sprite sheets](../technical/sprite-sheets.md), so Godot's first asset import handles about 5,200 files instead of about 123,000. A run from a fresh copy with both client archives already downloaded took 31 minutes on an M-series Mac at low priority (`nice`): extraction, every import with the 8.0 data, Godot's import and the web build. The test suites then passed in that copy. Later runs skip finished steps; `--import-only` re-runs the importers, Godot import and web build.

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
$PY tools/import_faces.py "$CLIENT"          # status window faces
$PY tools/import_pets.py "$CLIENT"
$PY tools/import_mirror.py "$CLIENT"          # 精灵 equipment art and the caster, mirror, heal and revive effects
$PY tools/import_loading.py "$CLIENT"        # web waiting screen (Ogg Vorbis, tools/music_codec.py)
$PY tools/import_music.py "$CLIENT"          # the music library: map, battle and 电台 music; the 8.0 folder has 26 tracks, 2.5 has 24
$PY tools/import_riding.py "$CLIENT"         # after characters: riders are checked against them
#   with the 8.0 data: add --extra-source .tools/legacy/extracted/SA8.0-20260803
$PY tools/import_grid_cursor.py "$CLIENT"
$PY tools/import_cursor.py 'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/123.cur'
python3 tools/import_encounters.py
$PY tools/import_encounter_art.py "$CLIENT"   # every pet's battle sprite; add --extra-source <8.0 data> for the 8.0-only ones
$PY tools/import_battle_sounds.py "$CLIENT" --table 'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/systeminc/sndcnf.h'
#   after the sprite importers: every frame's original SE and hit sound
$PY tools/pack_frame_sheets.py                # per-frame PNGs into sprite sheets
python3 tools/split_manifests.py              # last: the per-sprite files and indexes the game reads
./scripts/build-fast-hunt.sh                  # optional: the pet hunt's 本机极速模式 helper (needs a C compiler)
./scripts/run.sh --headless --editor --import --quit
./scripts/build-web.sh                        # optional: the web client (needs the web export templates)
```

On Windows the venv's Python is `.tools/asset-venv/Scripts/python.exe`; set `PYTHONUTF8=1` when running the importers by hand.

The client folder must contain `data/adrn_<n>.bin`, `real_<n>.bin`, `spradrn_<n>.bin`, `spr_<n>.bin`, `pal/Palet_1.sap`, the audio files and `map/1000.DAT`. `Archive` (`tools/import_legacy.py`) takes the highest-numbered file of each kind (2.5: `adrn_15`, `real_15`, `spradrn_5`, `spr_4`; 8.0: `adrn_136`, `real_136`, `spradrn_115`, `spr_115`; `adrntrue_*`/`realtrue_*` are other files) and finds the palette case-insensitively (8.0 names it `PALET_1.SAP`). The 8.0 data has no `map/` folder, so only the riding, pet art and music imports use it. `--server-map` reads the original Samgir layout from the server data instead of the client cache's later decorations; unresolved decorations are recorded, never replaced with invented art. See [resource evidence](../reverse-engineering/samgir-import.md) for formats and hashes.

After re-importing maps or encounters, regenerate the tracked spot indexes: `python3 tools/build_training_spots.py` and `python3 tools/build_level_one_spots.py`.

`import_world.py` writes each map as `world/<id>.map`, a compact file the game reads into packed arrays (`tools/map_file.py`, `client/scripts/map_file.gd`). A checkout imported before that has `world/<id>.json` instead; convert it in place without re-importing (seconds, no original files needed; it checks every map reads back the same before deleting its JSON):

```sh
python3 tools/map_file.py
```

`samgir.json`, `shop.json` and `wilderness.json` stay JSON: later importers read them, and the game uses them only when the world manifest lacks those maps.

## Decoding notes

Graphics use the original RLE format. Some original bitmaps' last run is one pixel longer than the image; the original client (`unpack.cpp`, `decoder()`) writes runs without a bound and keeps the first `width × height` bytes, so the importer clips the same way. This recovers six character appearances, the gold-tiger rider variant 101076 and the monster 凯比特 (100298). Appearance 100100 stays unavailable: its club sprite points at bitmap 4294967295 in every known client.
