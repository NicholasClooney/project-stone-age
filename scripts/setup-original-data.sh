#!/bin/sh
# From a fresh clone to a playable game: fetch the tools and original data this
# repository deliberately does not contain, then import it.
#
#   ./scripts/setup-original-data.sh            # everything needed to play on desktop
#   ./scripts/setup-original-data.sh --web      # also the Godot web export templates
#   ./scripts/setup-original-data.sh --with-8.0 # also the 8.0 client data (1.2 GB download),
#                                               # used for the certificate ride mounts and
#                                               # about 300 pet battle sprites
#   ./scripts/setup-original-data.sh --import-only   # re-run the importers only
#                                                    # (add --with-8.0 to keep the 8.0 mounts)
#
# Steps (each skipped when already done):
#   1. Godot 4.6 into .tools/Godot.app (macOS; elsewhere put `godot` on PATH)
#   2. Python venv .tools/asset-venv with tools/requirements.txt
#   3. Reference source repositories into references/ at the pinned revisions
#      in docs/reverse-engineering/local-references.json (server data, maps,
#      NPC scripts and client source the importers read)
#   4. The community-distributed 2.5 client (99ds.com) into .tools/legacy/,
#      checked against its recorded SHA-256, extracted without executables
#   5. Every importer, in dependency order, then Godot's asset import
# Original assets stay local (gitignored). Nothing downloaded is ever executed:
# executables and libraries are excluded when extracting the game clients.
# See docs/development/original-data-setup.md.
set -eu
cd "$(dirname "$0")/.."

GODOT_VERSION=4.6-stable
GODOT_URL="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_macos.universal.zip"
TEMPLATES_URL="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_export_templates.tpz"
CLIENT25_URL="https://99ds.com/downloads/windows/Stoneage2.5-Windows.rar"
CLIENT25_SHA256=0e157c0fcfe2bcf91826907d580d4403138d86fab9488aa39cd9494af17449ae
CLIENT25_ARCHIVE=.tools/legacy/client25.rar
CLIENT25=.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
CLIENT80_URL="https://99ds.com/downloads/windows/Stoneage8.0-Windows.zip"
CLIENT80_SHA256=48bef440851d361d699358ab70ffbd38f6b92c6263fb243863987fb54998475e
CLIENT80_ARCHIVE=.tools/legacy/Stoneage8.0-Windows.zip
CLIENT80=.tools/legacy/extracted/SA8.0-20260803
SERVER=references/chenmingbiao-stone-age
CLIENT_SOURCE=references/anson1788-stoneage
PY=.tools/asset-venv/bin/python

web=0
with80=0
import_only=0
for argument in "$@"; do
  case "$argument" in
    --web) web=1 ;;
    --with-8.0) with80=1 ;;
    --import-only) import_only=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $argument (see --help)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1 ($2)" >&2; exit 1; }; }

download() {
  # download <url> <file> <sha256>: resumable, then verified.
  mkdir -p "$(dirname "$2")"
  if [ -f "$2" ] && [ "$(shasum -a 256 "$2" | cut -d' ' -f1)" = "$3" ]; then
    echo "Already downloaded: $2"
    return
  fi
  curl -L --fail -C - --retry 5 --retry-delay 5 -o "$2" "$1"
  actual=$(shasum -a 256 "$2" | cut -d' ' -f1)
  if [ "$actual" != "$3" ]; then
    echo "WARNING: $2 has SHA-256 $actual, expected $3." >&2
    echo "  The upstream file changed. Imports may differ from the documented ones; check before relying on it." >&2
  fi
}

engine() {
  if [ -n "${GODOT_BIN:-}" ]; then echo "$GODOT_BIN"
  elif [ -x .tools/Godot.app/Contents/MacOS/Godot ]; then echo .tools/Godot.app/Contents/MacOS/Godot
  elif command -v godot >/dev/null 2>&1; then echo godot
  fi
}

need curl "download tool"
need python3 "Python 3.10 or later"
need git "to clone the reference repositories"
need shasum "checksums (part of Perl; on Linux install perl or coreutils' sha256sum wrapper)"
need bsdtar "extracts the RAR/ZIP clients (macOS built in; Linux: libarchive-tools)"

if [ "$import_only" = 0 ]; then
  step "Godot $GODOT_VERSION"
  if [ -n "$(engine)" ]; then
    echo "Found: $(engine)"
  elif [ "$(uname)" = Darwin ]; then
    mkdir -p .tools
    curl -L --fail -o .tools/godot.zip "$GODOT_URL"
    bsdtar -xf .tools/godot.zip -C .tools
    rm .tools/godot.zip
    echo "Installed .tools/Godot.app"
  else
    echo "Install Godot $GODOT_VERSION and put it on PATH as 'godot' (or set GODOT_BIN), then rerun." >&2
    exit 1
  fi

  if [ "$web" = 1 ]; then
    step "Godot web export templates"
    if [ "$(uname)" = Darwin ]; then
      templates="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION%-stable}.stable"
    else
      templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION%-stable}.stable"
    fi
    if ls "$templates"/web_*.zip >/dev/null 2>&1; then
      echo "Found: $templates"
    else
      mkdir -p "$templates" .tools
      curl -L --fail -C - -o .tools/export_templates.tpz "$TEMPLATES_URL"
      # Only the web templates are needed.
      bsdtar -xf .tools/export_templates.tpz -C .tools 'templates/web_*'
      mv .tools/templates/web_* "$templates"/
      rm -rf .tools/templates .tools/export_templates.tpz
      echo "Installed web templates into $templates"
    fi
  fi

  step "Python tools"
  if [ ! -x "$PY" ]; then python3 -m venv .tools/asset-venv; fi
  "$PY" -m pip install --quiet -r tools/requirements.txt
  command -v ffmpeg >/dev/null 2>&1 || echo "Note: ffmpeg not found; the web waiting music is kept as WAV (larger). Optional."

  step "Reference repositories"
  python3 - <<'EOF'
import json, subprocess, os
manifest = json.load(open('docs/reverse-engineering/local-references.json'))
for repo in manifest['repositories']:
    checkout, head = repo['checkout'], repo['head']
    if not os.path.isdir(os.path.join(checkout, '.git')):
        bundle = repo.get('bundle', '')
        source = bundle if bundle and os.path.exists(bundle) else repo['repository']
        print(f'Cloning {source} -> {checkout}')
        subprocess.run(['git', 'clone', '--quiet', source, checkout], check=True)
    actual = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=checkout, capture_output=True, text=True, check=True).stdout.strip()
    if actual != head:
        subprocess.run(['git', 'checkout', '--quiet', head], cwd=checkout, check=True)
    print(f'{checkout} at {head[:12]}')
EOF

  step "StoneAge 2.5 client (about 550 MB)"
  if [ -f "$CLIENT25/data/adrn_15.bin" ]; then
    echo "Found: $CLIENT25"
  else
    download "$CLIENT25_URL" "$CLIENT25_ARCHIVE" "$CLIENT25_SHA256"
    mkdir -p .tools/legacy/extracted
    bsdtar -xf "$CLIENT25_ARCHIVE" -C .tools/legacy/extracted \
      --exclude '*.exe' --exclude '*.EXE' --exclude '*.dll' --exclude '*.DLL' \
      --exclude '*.ocx' --exclude '*.OCX' --exclude '*.bat' --exclude '*.BAT' --exclude '*.scr'
    [ -f "$CLIENT25/data/adrn_15.bin" ] || { echo "Unexpected archive layout: $CLIENT25/data/adrn_15.bin not found." >&2; exit 1; }
  fi

  if [ "$with80" = 1 ]; then
    step "StoneAge 8.0 client data (1.2 GB download, data folder only)"
    if [ -f "$CLIENT80/data/adrn_136.bin" ]; then
      echo "Found: $CLIENT80"
    else
      download "$CLIENT80_URL" "$CLIENT80_ARCHIVE" "$CLIENT80_SHA256"
      # Entry names are GBK; extract only data/, never the executables beside it.
      python3 - "$CLIENT80_ARCHIVE" "$CLIENT80" <<'EOF'
import os, shutil, sys, zipfile
archive, dest = sys.argv[1], sys.argv[2]
blocked = ('.exe', '.dll', '.ocx', '.bat', '.cmd', '.vbs', '.scr')
count = 0
with zipfile.ZipFile(archive) as z:
    for info in z.infolist():
        name = info.filename
        if not info.flag_bits & 0x800:
            try:
                name = name.encode('cp437').decode('gbk')
            except UnicodeError:
                pass
        if '/data/' not in name or name.endswith('/') or name.lower().endswith(blocked):
            continue
        out = os.path.join(dest, 'data', name.split('/data/', 1)[1])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with z.open(info) as source, open(out, 'wb') as target:
            shutil.copyfileobj(source, target, 1 << 20)
        count += 1
print(f'Extracted {count} data files to {dest}')
EOF
    fi
  fi
fi

[ -f "$CLIENT25/data/adrn_15.bin" ] || { echo "No 2.5 client at $CLIENT25; run without --import-only first." >&2; exit 1; }
[ -x "$PY" ] || { echo "No Python tools at $PY; run without --import-only first." >&2; exit 1; }
[ -d "$SERVER/gmsv" ] || { echo "No server reference at $SERVER; run without --import-only first." >&2; exit 1; }
riding_extra=""
if [ "$with80" = 1 ]; then
  [ -f "$CLIENT80/data/adrn_136.bin" ] || { echo "No 8.0 data at $CLIENT80; run with --with-8.0 but without --import-only first." >&2; exit 1; }
  riding_extra="--extra-source $CLIENT80"
fi

step "Importing original resources (several minutes)"
run() { echo "-- $*"; "$@"; }
run "$PY" tools/import_legacy.py "$CLIENT25" --server-map "$SERVER/gmsv/data/map/sainasu/samugiru/samugiru"
run "$PY" tools/import_ui.py "$CLIENT25"
run "$PY" tools/import_npc.py "$CLIENT25" "$SERVER/gmsv/data/npc"
run "$PY" tools/import_wilderness.py "$CLIENT25" --server-map "$SERVER/gmsv/data/map/sainasu/sainasu"
run "$PY" tools/import_battle.py "$CLIENT25"
run "$PY" tools/import_battle_backgrounds.py "$CLIENT25"
run "$PY" tools/import_mvp.py "$CLIENT25"
run "$PY" tools/import_world.py "$CLIENT25"
run "$PY" tools/import_pet_training.py "$CLIENT25"
run "$PY" tools/import_characters.py "$CLIENT25"
run "$PY" tools/import_faces.py "$CLIENT25"
run "$PY" tools/import_pets.py "$CLIENT25"
run "$PY" tools/import_mirror.py "$CLIENT25"
run "$PY" tools/import_loading.py "$CLIENT25"
# The radio takes the 8.0 soundtrack (26 tracks) when it is extracted, else 2.5's 24.
if [ -d "$CLIENT80/data/bgm" ]; then run "$PY" tools/import_music.py "$CLIENT80"; else run "$PY" tools/import_music.py "$CLIENT25"; fi
# With --with-8.0 the riding import adds the certificate mounts only 8.0 has.
# shellcheck disable=SC2086
run "$PY" tools/import_riding.py "$CLIENT25" $riding_extra
run "$PY" tools/import_grid_cursor.py "$CLIENT25"
run "$PY" tools/import_cursor.py "$CLIENT_SOURCE/石器时代8.5客户端最新源代码/石器源码/123.cur"
run python3 tools/import_encounters.py
# Every pet template's battle sprite; with --with-8.0 also the 313 only 8.0 has (机豹, 黑乌力王, the album pets).
# shellcheck disable=SC2086
run "$PY" tools/import_encounter_art.py "$CLIENT25" $riding_extra
# After every sprite importer: each frame's original sound effect and hit sound.
run "$PY" tools/import_battle_sounds.py "$CLIENT25" --table "$CLIENT_SOURCE/石器时代8.5客户端最新源代码/石器源码/systeminc/sndcnf.h"
# Last: packs the per-frame PNGs the importers above wrote into sprite sheets.
run "$PY" tools/pack_frame_sheets.py

step "本机极速模式 helper for the pet hunt"
./scripts/build-fast-hunt.sh

step "Godot asset import (the first run takes about half an hour)"
./scripts/run.sh --headless --editor --import --quit >/dev/null 2>&1

step "Done"
echo "Play:        ./scripts/run.sh"
echo "Tests:       ./scripts/test-all.sh"
[ "$web" = 1 ] && echo "Web client:  ./scripts/build-web.sh && ./scripts/serve.sh"
exit 0
