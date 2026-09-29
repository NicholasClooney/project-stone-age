#!/bin/sh
# Build the web client into build/web: the engine and game scripts without
# original assets, plus content-hashed asset packs the page downloads on demand.
# Requires imported original assets and the Godot 4.6 web export templates.
#
# Incremental: the export's editor start imports only changed assets, and packs
# whose source files are unchanged since the last build are reused (cache in
# build/web-packs/cache.json), so a code-only rebuild mostly costs the export.
# Delete build/web-packs/cache.json to force every pack to be rewritten.
set -eu
cd "$(dirname "$0")/.."
if [ -n "${GODOT_BIN:-}" ]; then
  engine="$GODOT_BIN"
elif [ -x .tools/Godot.app/Contents/MacOS/Godot ]; then
  engine=.tools/Godot.app/Contents/MacOS/Godot
else
  engine=godot
fi
# One build at a time: two overlapping builds delete each other's packs.
mkdir -p build
if ! mkdir build/.web-build.lock 2>/dev/null; then
  echo "Another web build is running (remove build/.web-build.lock if it was interrupted)." >&2
  exit 1
fi
trap 'rm -rf build/.web-build.lock build/web/packs.new build/web-export' EXIT INT TERM
python3 tools/plan_web_packs.py
# Export first, into a staging folder: its editor start also imports changed
# assets, which the packs below are built from.
rm -rf build/web-export
mkdir -p build/web-export
"$engine" --headless --path client --export-release Web ../build/web-export/index.html
# Loaded in <head> before the engine (export preset html/head_include): keeps
# sound alive across system audio interruptions, see web/audio_session.js.
cp web/audio_session.js build/web-export/
# Packs are built beside the served set and swapped in only when complete, so
# a failed or interrupted build never leaves a page without packs.json. The new
# set starts as a copy-on-write clone of the served one; unchanged packs stay.
rm -rf build/web/packs.new
if [ -d build/web/packs ]; then
  cp -c -R build/web/packs build/web/packs.new 2>/dev/null || cp -R build/web/packs build/web/packs.new
fi
"$engine" --headless --path client --audio-driver Dummy --script res://tools/build_web_packs.gd -- "$PWD/build/web-packs/plan.json" "$PWD/build/web/packs.new" "$PWD/build/web-packs/cache.json"
if [ ! -f build/web/packs.new/packs.json ]; then
  echo "Asset pack build failed; the previous build is still in place." >&2
  exit 1
fi
mkdir -p build/web
mv build/web-export/* build/web/
rm -rf build/web/packs.old
[ -d build/web/packs ] && mv build/web/packs build/web/packs.old
mv build/web/packs.new build/web/packs
rm -rf build/web/packs.old
echo "Web build ready in build/web; serve it with scripts/serve.sh"
