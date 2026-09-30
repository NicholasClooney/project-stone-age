#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
require_godot
# The pet hunt's 本机极速模式 helper; without a compiler the hunt scans in GDScript.
./scripts/build-fast-hunt.sh --quiet || true
if [ ! -d client/.godot/imported ]; then
  "$engine" --headless --path client --editor --import --quit
fi
# A test suite gets its own user:// folder, never the game's real one where
# the live save lives: client/scripts/test_user_dir.gd reads
# STONE_AGE_TEST_USER_DIR (relative to the OS data folder). By default each
# checkout has one folder; scripts/test-all.sh gives every suite its own.
script=""
previous=""
for argument in "$@"; do
  [ "$argument" = "--" ] && break
  case "$previous" in --script|-s) script="$argument" ;; esac
  previous="$argument"
done
case "$script" in
  res://tests/*)
    if [ -z "${STONE_AGE_TEST_USER_DIR:-}" ]; then
      checkout=$(pwd -P)
      STONE_AGE_TEST_USER_DIR="Godot/app_userdata/Stone Age tests/$(basename "$checkout")-$(printf '%s' "$checkout" | cksum | cut -d ' ' -f 1)"
    fi
    export STONE_AGE_TEST_USER_DIR
    case "$platform" in
      macos) data_root="$HOME/Library/Application Support" ;;
      windows) data_root=$(native_path "${APPDATA:-$HOME/AppData/Roaming}") ;;
      *) data_root="${XDG_DATA_HOME:-$HOME/.local/share}" ;;
    esac
    # Godot's own log would otherwise rotate the real game's user://logs.
    set -- --log-file "$data_root/$STONE_AGE_TEST_USER_DIR/logs/godot.log" "$@"
    ;;
esac
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
