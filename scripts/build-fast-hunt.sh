#!/bin/sh
# Builds the 本机极速模式 helper (tools/fast_hunt/fast_hunt.c) into
# build/fast_hunt when it is missing or was built from a different source.
# build/fast_hunt.source keeps the checksum of the source it was built from:
# modification times are no guide, since a worktree copies the binary from
# another checkout (newer than any source) and a checkout changes the source.
# Without a C compiler the helper stays unavailable and the pet hunt scans in
# GDScript. run.sh and serve.sh call this quietly; --quiet prints nothing on
# success. Parallel calls (test-all.sh) each build into their own temporary
# file and move it into place, so none sees a half-written helper.
set -eu
cd "$(dirname "$0")/.."
source=tools/fast_hunt/fast_hunt.c
target=build/fast_hunt
quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1
checksum=$(cksum < "$source")
if [ -x "$target" ] && [ "$(cat "$target.source" 2>/dev/null)" = "$checksum" ]; then
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
if "$compiler" -O2 -pthread -o "$target.new.$$" "$source"; then
  mv "$target.new.$$" "$target"
  printf '%s\n' "$checksum" > "$target.source.$$"
  mv "$target.source.$$" "$target.source"
  [ "$quiet" = 1 ] || echo "Built $target"
else
  rm -f "$target.new.$$"
  echo "Could not build $target: 本机极速模式 stays off." >&2
fi
exit 0
