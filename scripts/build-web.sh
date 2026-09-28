#!/bin/sh
# Build the web client into build/web: the engine and game scripts without
# original assets, plus content-hashed asset packs the page downloads on demand.
# Requires imported original assets and the Godot 4.6 web export templates.
set -eu
cd "$(dirname "$0")/.."
if [ -n "${GODOT_BIN:-}" ]; then
  engine="$GODOT_BIN"
elif [ -x .tools/Godot.app/Contents/MacOS/Godot ]; then
  engine=.tools/Godot.app/Contents/MacOS/Godot
else
  engine=godot
fi
"$engine" --headless --path client --editor --import --quit >/dev/null 2>&1
# One build at a time: two overlapping builds delete each other's packs.
mkdir -p build
if ! mkdir build/.web-build.lock 2>/dev/null; then
  echo "Another web build is running (remove build/.web-build.lock if it was interrupted)." >&2
  exit 1
fi
trap 'rm -rf build/.web-build.lock build/web/packs.new' EXIT INT TERM
python3 tools/plan_web_packs.py
# Packs are built beside the served set and swapped in only when complete, so
# a failed or interrupted build never leaves a page without packs.json.
rm -rf build/web/packs.new
"$engine" --headless --path client --audio-driver Dummy --script res://tools/build_web_packs.gd -- "$PWD/build/web-packs/plan.json" "$PWD/build/web/packs.new"
if [ ! -f build/web/packs.new/packs.json ]; then
  echo "Asset pack build failed; the previous packs are still in place." >&2
  exit 1
fi
"$engine" --headless --path client --export-release Web ../build/web/index.html
rm -rf build/web/packs.old
[ -d build/web/packs ] && mv build/web/packs build/web/packs.old
mv build/web/packs.new build/web/packs
rm -rf build/web/packs.old
echo "Web build ready in build/web; serve it with scripts/serve.sh"
