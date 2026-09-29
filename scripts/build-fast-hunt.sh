#!/bin/sh
# Builds the 本机极速模式 helper (tools/fast_hunt/fast_hunt.c) into
# build/fast_hunt when it is missing or older than its source. Without a C
# compiler the helper stays unavailable and the pet hunt scans in GDScript.
# run.sh and serve.sh call this quietly; --quiet prints nothing on success.
set -eu
cd "$(dirname "$0")/.."
source=tools/fast_hunt/fast_hunt.c
target=build/fast_hunt
quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1
if [ -x "$target" ] && [ "$target" -nt "$source" ]; then
  exit 0
fi
compiler="${CC:-}"
if [ -z "$compiler" ]; then
  for candidate in cc clang gcc; do
    if command -v "$candidate" >/dev/null 2>&1; then compiler="$candidate"; break; fi
  done
fi
if [ -z "$compiler" ]; then
  echo "No C compiler found: 本机极速模式 stays off and the pet hunt scans in GDScript." >&2
  exit 0
fi
mkdir -p build
if "$compiler" -O2 -pthread -o "$target.new" "$source"; then
  mv "$target.new" "$target"
  [ "$quiet" = 1 ] || echo "Built $target"
else
  rm -f "$target.new"
  echo "Could not build $target: 本机极速模式 stays off." >&2
fi
exit 0
