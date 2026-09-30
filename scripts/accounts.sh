#!/bin/sh
# Accounts of a multi-profile server (scripts/serve.sh --accounts=...; see
# docs/development/lan-profiles.md):
#   scripts/accounts.sh list
#   scripts/accounts.sh add <name> [--save=user://single-player.json] [--admin]
#   scripts/accounts.sh pin <name>          # new PIN
#   scripts/accounts.sh admin <name> on|off
#   scripts/accounts.sh create on|off       # may clients create characters
#   scripts/accounts.sh remove <name>       # the save stays
# The file is user://lan/accounts.json unless --accounts=<file> is given.
# add and pin ask for the PIN (4 to 8 digits) without echoing it; set
# STONE_AGE_PIN to skip the prompt. A running server sees changes at the next
# login.
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
command=""
for argument in "$@"; do
  case "$argument" in --*) ;; *) command="$argument"; break ;; esac
done
if { [ "$command" = add ] || [ "$command" = pin ]; } && [ -z "${STONE_AGE_PIN:-}" ]; then
  printf 'PIN (4 to 8 digits): '
  stty -echo 2>/dev/null || true
  read -r first
  stty echo 2>/dev/null || true
  printf '\nPIN again: '
  stty -echo 2>/dev/null || true
  read -r second
  stty echo 2>/dev/null || true
  printf '\n'
  if [ "$first" != "$second" ]; then
    echo 'The two PINs differ.' >&2
    exit 1
  fi
  STONE_AGE_PIN="$first"
fi
export STONE_AGE_PIN="${STONE_AGE_PIN:-}"
exec "$engine" --headless --path client --audio-driver Dummy --script res://server/accounts_tool.gd -- "$@"
