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
# The pet hunt's 本机极速模式 helper; without a compiler the hunt scans in GDScript.
./scripts/build-fast-hunt.sh --quiet || true
if [ ! -d client/.godot/imported ]; then
  "$engine" --headless --path client --editor --import --quit
fi
# Automated verification must not steal focus or play desktop audio.
# Foreground visual testing requires an explicit user request and this opt-in.
for argument in "$@"; do
  case "$argument" in
    --) break ;;
    --script|-s)
      if [ "${STONE_AGE_FOREGROUND_TEST:-0}" = "1" ]; then
        exec "$engine" --path client --audio-driver Dummy "$@"
      fi
      exec "$engine" --path client --headless --audio-driver Dummy "$@"
      ;;
    --headless)
      exec "$engine" --path client --audio-driver Dummy "$@"
      ;;
  esac
done
exec "$engine" --path client "$@"
