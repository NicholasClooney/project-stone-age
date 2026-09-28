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
python3 tools/plan_web_packs.py
rm -rf build/web/packs
"$engine" --headless --path client --audio-driver Dummy --script res://tools/build_web_packs.gd -- "$PWD/build/web-packs/plan.json" "$PWD/build/web/packs"
"$engine" --headless --path client --export-release Web ../build/web/index.html
echo "Web build ready in build/web; serve it with scripts/serve.sh"
