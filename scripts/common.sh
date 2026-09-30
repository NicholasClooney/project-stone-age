# Shared by the scripts in this folder: the platform, Godot and Python.
# Source it from the repository root: `. scripts/common.sh`.
# Works in macOS, Linux, WSL2 and Git Bash / MSYS2 on Windows.
# shellcheck shell=sh

GODOT_VERSION=4.6-stable

# The tools read and write UTF-8 text (Chinese names, JSON) whatever the
# system code page; Windows' default one would break them.
export PYTHONUTF8=1

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then platform=wsl; else platform=linux; fi ;;
  MINGW*|MSYS*|CYGWIN*) platform=windows ;;
  *) platform=other ;;
esac

# native_path PATH: PATH as a Windows program (Godot, Python) reads it. Git
# Bash's /c/Users/... becomes C:/Users/...; unchanged elsewhere.
native_path() {
  if [ "$platform" = windows ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s\n' "$1"
  fi
}

# The Godot binaries scripts/setup-original-data.sh installs into .tools/.
# On Windows the console build: it prints to the terminal and is waited for.
godot_downloads() {
  case "$platform-$(uname -m)" in
    macos-*) echo "macos.universal.zip .tools/Godot.app/Contents/MacOS/Godot" ;;
    linux-x86_64|wsl-x86_64) echo "linux.x86_64.zip .tools/godot/Godot_v${GODOT_VERSION}_linux.x86_64" ;;
    linux-aarch64|wsl-aarch64|linux-arm64) echo "linux.arm64.zip .tools/godot/Godot_v${GODOT_VERSION}_linux.arm64" ;;
    windows-x86_64) echo "win64.exe.zip .tools/godot/Godot_v${GODOT_VERSION}_win64_console.exe" ;;
    windows-aarch64|windows-arm64) echo "windows_arm64.exe.zip .tools/godot/Godot_v${GODOT_VERSION}_windows_arm64_console.exe" ;;
  esac
}

# find_godot: prints the Godot 4.6 executable to use, or nothing.
# GODOT_BIN wins, then the copy in .tools/, then `godot` on PATH.
find_godot() {
  if [ -n "${GODOT_BIN:-}" ]; then echo "$GODOT_BIN"; return; fi
  bundled=$(godot_downloads | cut -d' ' -f2)
  if [ -n "$bundled" ] && [ -x "$bundled" ]; then echo "$bundled"; return; fi
  for name in godot godot4; do
    if command -v "$name" >/dev/null 2>&1; then echo "$name"; return; fi
  done
  if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then echo /Applications/Godot.app/Contents/MacOS/Godot; fi
}

require_godot() {
  engine=$(find_godot)
  if [ -z "$engine" ]; then
    echo "Godot 4.6 not found: run ./scripts/setup-original-data.sh, install it as 'godot', or set GODOT_BIN." >&2
    exit 1
  fi
}

# find_python: prints a Python 3.10+ command. On Windows `python3` is often
# the Microsoft Store placeholder, so each candidate must actually run.
find_python() {
  for candidate in python3 python py; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if [ "$candidate" = py ]; then
      # The launcher takes a version flag; hand back the interpreter it picks.
      found=$(py -3 -c 'import sys; print(sys.executable if sys.version_info >= (3, 10) else "")' 2>/dev/null | tr -d '\r') || continue
      [ -n "$found" ] && { native_unix "$found"; return; }
    elif "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
      echo "$candidate"; return
    fi
  done
}

native_unix() {
  if [ "$platform" = windows ] && command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}

require_python() {
  PYTHON=$(find_python)
  if [ -z "$PYTHON" ]; then
    echo "Python 3.10 or later not found (python3, python or py)." >&2
    exit 1
  fi
}

# listening PORT: true when something accepts TCP connections on PORT here.
# lsof where it exists; Git Bash has none, so there a local connect decides.
listening() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    "${PYTHON:-python3}" -c 'import socket, sys
s = socket.socket(); s.settimeout(0.5)
sys.exit(s.connect_ex(("127.0.0.1", int(sys.argv[1]))) != 0)' "$1" >/dev/null 2>&1
  fi
}

# The asset tools' virtual environment (bin/ on Unix, Scripts/ on Windows).
venv_python() {
  for candidate in .tools/asset-venv/bin/python .tools/asset-venv/Scripts/python.exe; do
    if [ -x "$candidate" ]; then echo "$candidate"; return; fi
  done
}
