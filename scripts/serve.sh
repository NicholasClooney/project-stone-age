#!/bin/sh
# Run the headless backend that remote clients (the web build) connect to.
# Options: --port=8765 --bind=* --save=user://single-player.json
# Stop with Ctrl-C; progress is saved after every settlement and on exit.
set -eu
cd "$(dirname "$0")/.."
if [ -n "${GODOT_BIN:-}" ]; then
  engine="$GODOT_BIN"
elif [ -x .tools/Godot.app/Contents/MacOS/Godot ]; then
  engine=.tools/Godot.app/Contents/MacOS/Godot
elif command -v godot >/dev/null 2>&1; then
  engine=godot
else
  echo 'Install Godot 4.6, or set GODOT_BIN to its executable.' >&2
  exit 1
fi
exec "$engine" --headless --path client --audio-driver Dummy --script res://server/server_main.gd -- "$@"
