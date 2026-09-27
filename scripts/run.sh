#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -n "${GODOT_BIN:-}" ]; then
  engine="$GODOT_BIN"
elif [ -x .tools/Godot.app/Contents/MacOS/Godot ]; then
  engine=.tools/Godot.app/Contents/MacOS/Godot
elif command -v godot >/dev/null 2>&1; then
  engine=godot
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  engine=/Applications/Godot.app/Contents/MacOS/Godot
else
  echo 'Install Godot 4.6, or set GODOT_BIN to its executable.' >&2
  exit 1
fi
if [ ! -d client/.godot/imported ]; then
  "$engine" --headless --path client --editor --import --quit
fi
# Scripted verification must not play audio into the user's desktop.
for argument in "$@"; do
  case "$argument" in
    --) break ;;
    --script|-s|--headless)
      exec "$engine" --path client --audio-driver Dummy "$@"
      ;;
  esac
done
exec "$engine" --path client "$@"
