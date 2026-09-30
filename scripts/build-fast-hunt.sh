#!/bin/sh
# Builds the 本机极速模式 helper (tools/fast_hunt/fast_hunt.c) into
# build/fast_hunt (build/fast_hunt.exe on Windows) when it is missing or was
# built from a different source.
# build/fast_hunt.source keeps the checksum of the source it was built from:
# modification times are no guide, since a worktree copies the binary from
# another checkout (newer than any source) and a checkout changes the source.
# Without a C compiler the helper stays unavailable and the pet hunt scans in
# GDScript. run.sh and serve.sh call this quietly; --quiet prints nothing on
# success. Parallel calls (test-all.sh) each build into their own temporary
# file and move it into place, so none sees a half-written helper.
# Windows (Git Bash): needs MinGW-w64 gcc (MSYS2's mingw-w64-ucrt-x86_64-gcc,
# or WinLibs / w64devkit on PATH); MSVC has no pthreads and is not used.
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
source=tools/fast_hunt/fast_hunt.c
target=build/fast_hunt
staged="build/fast_hunt.new.$$"
flags="-O2 -pthread"
libraries=""
if [ "$platform" = windows ]; then
  target=build/fast_hunt.exe
  # MinGW's linker appends .exe to an output name without it.
  staged="build/fast_hunt.new.$$.exe"
  # Static, so it runs without MinGW's DLLs on PATH when Godot starts it.
  flags="$flags -static"
  libraries="-lshell32"
fi
quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1
checksum=$(cksum < "$source")
if [ -x "$target" ] && [ "$(cat "$target.source" 2>/dev/null)" = "$checksum" ]; then
  exit 0
fi
compiler="${CC:-}"
if [ -z "$compiler" ]; then
  for candidate in cc gcc clang; do
    if command -v "$candidate" >/dev/null 2>&1; then compiler="$candidate"; break; fi
  done
fi
if [ -z "$compiler" ]; then
  echo "No C compiler found: 本机极速模式 stays off and the pet hunt scans in GDScript." >&2
  exit 0
fi
mkdir -p build
# shellcheck disable=SC2086
if "$compiler" $flags -o "$staged" "$source" $libraries; then
  mv "$staged" "$target"
  printf '%s\n' "$checksum" > "$target.source.$$"
  mv "$target.source.$$" "$target.source"
  [ "$quiet" = 1 ] || echo "Built $target"
else
  rm -f "$staged"
  echo "Could not build $target: 本机极速模式 stays off and the pet hunt scans in GDScript." >&2
fi
exit 0
