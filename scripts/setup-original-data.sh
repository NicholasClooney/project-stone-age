#!/bin/sh
# From a fresh clone to everything a working checkout has: fetch the tools and
# original data this repository deliberately does not contain, import it, and
# build the pet hunt helper, Godot's asset import and the web client.
#
#   ./scripts/setup-original-data.sh             # everything; shows sizes, asks first
#   ./scripts/setup-original-data.sh --yes       # everything, no question
#   ./scripts/setup-original-data.sh --dry-run   # only show what it would download and store
#
# Options:
#   --no-8.0       skip the 8.0 client data (1.2 GB download, 1.8 GB extracted): without it
#                  313 pet battle sprites, the later certificate ride mounts and the
#                  radio's two extra tracks are missing
#   --no-web       skip the web export templates and the web build (browser, Vision Pro,
#                  several devices); build it later with this script or scripts/build-web.sh
#   --import-only  download nothing; re-run the importers, then the helper, Godot's
#                  import and the web build (for example after an importer changes)
#   -y, --yes      do not ask before downloading
#   --dry-run      print the plan and exit
#
# Steps, each skipped when already done (rerun after an interruption to resume;
# downloads continue where they stopped and are checked by size and SHA-256):
#    1. Godot 4.6 into .tools/ (Godot.app on macOS, .tools/godot/ on Linux, WSL, Windows)
#    2. Godot's web export templates (only the web ones, about 40 MB of the 1.25 GB archive)
#    3. Python venv .tools/asset-venv with tools/requirements.txt
#    4. Reference source repositories into references/ at the pinned revisions
#       in docs/reverse-engineering/local-references.json
#    5. The community-distributed 2.5 client (99ds.com) into .tools/legacy/
#    6. The 8.0 client's data folder (same site)
#    7. Every importer, in dependency order
#    8. The pet hunt's 本机极速模式 helper (needs a C compiler; optional)
#    9. Godot's asset import
#   10. The web client in build/web
# Original assets stay local (gitignored). Nothing downloaded is ever executed:
# executables and libraries are excluded when extracting the game clients.
# Works on macOS, Linux, WSL2 and Git Bash on Windows.
# See docs/development/original-data-setup.md.
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh

GODOT_RELEASE="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION"
TEMPLATES_URL="$GODOT_RELEASE/Godot_v${GODOT_VERSION}_export_templates.tpz"
TEMPLATES_BYTES=1251639300
# Only these are fetched from the template archive (web_* with and without threads).
WEB_TEMPLATES_BYTES=39348062
CLIENT25_URL="https://99ds.com/downloads/windows/Stoneage2.5-Windows.rar"
CLIENT25_BYTES=553320338
CLIENT25_SHA256=0e157c0fcfe2bcf91826907d580d4403138d86fab9488aa39cd9494af17449ae
CLIENT25_ARCHIVE=.tools/legacy/client25.rar
CLIENT25_ROOT=.tools/legacy/extracted/SA2.5-20260823
CLIENT25=$CLIENT25_ROOT/SA2.5/stoneage2.5
CLIENT80_URL="https://99ds.com/downloads/windows/Stoneage8.0-Windows.zip"
CLIENT80_BYTES=1214843601
CLIENT80_SHA256=48bef440851d361d699358ab70ffbd38f6b92c6263fb243863987fb54998475e
CLIENT80_ARCHIVE=.tools/legacy/Stoneage8.0-Windows.zip
CLIENT80=.tools/legacy/extracted/SA8.0-20260803
SERVER=references/chenmingbiao-stone-age
CLIENT_SOURCE=references/anson1788-stoneage
IMPORT_STAMP=.tools/setup-import.stamp

with80=1
web=1
import_only=0
yes=0
dry_run=0
for argument in "$@"; do
  case "$argument" in
    --no-8.0) with80=0 ;;
    --no-web) web=0 ;;
    --import-only) import_only=1 ;;
    -y|--yes) yes=1 ;;
    --dry-run) dry_run=1 ;;
    --web|--with-8.0) ;;  # the default now; accepted for old instructions
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "Unknown option: $argument (see --help)" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }
mb() { awk -v b="$1" 'BEGIN { if (b >= 1e9) printf "%.2f GB", b / 1e9; else printf "%.0f MB", b / 1e6 }'; }
size_of() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# ---- Requirements -----------------------------------------------------------
hint() {
  case "$platform" in
    macos) echo "$1" ;;
    linux|wsl) echo "$2" ;;
    windows) echo "$3" ;;
    *) echo "$2" ;;
  esac
}
missing=""
need() { command -v "$1" >/dev/null 2>&1 || missing="$missing
  $1: $2"; }
need curl "$(hint 'built in' 'sudo apt install curl' 'included with Git for Windows')"
need git "$(hint 'xcode-select --install' 'sudo apt install git' 'install Git for Windows')"
PYTHON=$(find_python)
[ -n "$PYTHON" ] || missing="$missing
  python 3.10+: $(hint 'brew install python, or python.org' 'sudo apt install python3 python3-venv' 'winget install Python.Python.3.12')"
command -v sha256sum >/dev/null 2>&1 || need shasum "part of Perl; or install coreutils (sha256sum)"

# The RAR (RAR5) needs libarchive's bsdtar (built into macOS; Windows 10+ ships
# it as tar.exe, which reads RAR5 from libarchive 3.4 on), or 7-Zip.
find_extractor() {
  if command -v bsdtar >/dev/null 2>&1; then echo bsdtar; return; fi
  if tar --version 2>/dev/null | grep -q bsdtar; then echo tar; return; fi
  for candidate in 7z 7zz 7za; do
    if command -v "$candidate" >/dev/null 2>&1; then echo "$candidate"; return; fi
  done
  if [ "$platform" = windows ]; then
    # 7-Zip is rarely on PATH; Windows' own tar.exe is older on some Windows 10 builds.
    for candidate in "$(native_unix "${PROGRAMFILES:-C:/Program Files}")/7-Zip/7z.exe" "$(native_unix "${SYSTEMROOT:-C:/Windows}")/System32/tar.exe"; do
      if [ -x "$candidate" ]; then echo "$candidate"; return; fi
    done
  fi
}
extractor=$(find_extractor)

# ---- What is already done ----------------------------------------------------
godot_asset=$(godot_downloads | cut -d' ' -f1)
godot_binary=$(godot_downloads | cut -d' ' -f2)
godot_bytes=0
case "$godot_asset" in
  macos.universal.zip) godot_bytes=160610963 ;;
  linux.x86_64.zip) godot_bytes=71413330 ;;
  linux.arm64.zip) godot_bytes=70464543 ;;
  win64.exe.zip) godot_bytes=79418197 ;;
  windows_arm64.exe.zip) godot_bytes=77424238 ;;
esac
case "$platform" in
  macos) templates="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION%-stable}.stable" ;;
  windows) templates="$(native_unix "${APPDATA:-$HOME/AppData/Roaming}")/Godot/export_templates/${GODOT_VERSION%-stable}.stable" ;;
  *) templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION%-stable}.stable" ;;
esac
have_godot() { [ -n "$(find_godot)" ]; }
have_templates() { [ -f "$templates/web_nothreads_release.zip" ] && [ -f "$templates/web_nothreads_debug.zip" ]; }
have_venv() { [ -n "$(venv_python)" ]; }
have_references() { [ -d "$SERVER/.git" ] && [ -d "$CLIENT_SOURCE/.git" ]; }
have_client25() { [ -f "$CLIENT25/data/adrn_15.bin" ]; }
have_client80() { [ -f "$CLIENT80/data/adrn_136.bin" ]; }
bundles_present() {
  [ -f references/archives/anson1788-stoneage-2026-09-27.bundle ] && [ -f references/archives/chenmingbiao-stone-age-2026-09-27.bundle ]
}

# ---- Plan: sizes before anything is downloaded ---------------------------------
download_total=0
disk_total=0
plan_download() {
  # plan_download <label> <bytes> <state>
  printf '  %-48s %10s  %s\n' "$1" "$(mb "$2")" "$3"
  case "$3" in to\ download|resume*) download_total=$((download_total + $2)) ;; esac
}
plan_download_file() {
  # plan_download_file <label> <bytes> <archive> <done?>
  if [ "$4" = 1 ]; then plan_download "$1" "$2" "done"; return; fi
  have=$(size_of "$3")
  if [ "$have" -eq "$2" ]; then plan_download "$1" "$2" "downloaded"
  elif [ "$have" -gt 0 ] && [ "$have" -lt "$2" ]; then
    printf '  %-48s %10s  %s\n' "$1" "$(mb "$2")" "resume ($(mb $(($2 - have))) left)"
    download_total=$((download_total + $2 - have))
  else plan_download "$1" "$2" "to download"; fi
}
plan_disk() {
  # plan_disk <label> <megabytes> <done?>
  if [ "$3" = 1 ]; then state="present"; else state="new"; disk_total=$((disk_total + $2)); fi
  printf '  %-48s %10s  %s\n' "$1" "$(mb $(($2 * 1000000)))" "$state"
}
done_flag() { if "$@"; then echo 1; else echo 0; fi; }
[ -d client/.godot/imported ] && godot_imported=1 || godot_imported=0
[ -f build/web/packs/packs.json ] && web_built=1 || web_built=0
[ -d client/assets/legacy/battle ] && imported=1 || imported=0

echo "StoneAge setup ($platform): $( [ "$with80" = 1 ] && echo 'with' || echo 'without') the 8.0 data, $( [ "$web" = 1 ] && echo 'with' || echo 'without') the web client"
if [ "$import_only" = 0 ]; then
  echo
  echo "Downloads:"
  if [ -n "$godot_asset" ]; then
    plan_download_file "Godot $GODOT_VERSION ($godot_asset)" "$godot_bytes" ".tools/downloads/Godot_v${GODOT_VERSION}_$godot_asset" "$(done_flag have_godot)"
  elif ! have_godot; then
    echo "  Godot: no download for $(uname -s) $(uname -m); install Godot 4.6 as 'godot' or set GODOT_BIN"
  fi
  [ "$web" = 1 ] && plan_download "Godot web export templates (web_* only)" "$WEB_TEMPLATES_BYTES" "$(have_templates && echo 'done' || echo 'to download')"
  plan_download "Python packages (Pillow, soundfile, numpy)" 30000000 "$(have_venv && echo 'done' || echo 'to download')"
  if have_references; then plan_download "Reference repositories (git clone)" 170000000 "done"
  elif bundles_present; then plan_download "Reference repositories (git clone)" 170000000 "local bundles"
  else plan_download "Reference repositories (git clone)" 170000000 "to download"; fi
  plan_download_file "StoneAge 2.5 client (Stoneage2.5-Windows.rar)" "$CLIENT25_BYTES" "$CLIENT25_ARCHIVE" "$(done_flag have_client25)"
  [ "$with80" = 1 ] && plan_download_file "StoneAge 8.0 client (Stoneage8.0-Windows.zip)" "$CLIENT80_BYTES" "$CLIENT80_ARCHIVE" "$(done_flag have_client80)"
  printf '  %-48s %10s\n' "Total to download" "$(mb "$download_total")"
fi
echo
echo "Disk space afterwards (measured on a full checkout):"
if [ "$import_only" = 0 ]; then
  [ "$platform" = macos ] && godot_mb=342 || godot_mb=160
  [ -n "$godot_asset" ] && plan_disk "Godot" "$godot_mb" "$(done_flag have_godot)"
  [ "$web" = 1 ] && plan_disk "Web export templates" 40 "$(done_flag have_templates)"
  plan_disk "Python venv (.tools/asset-venv)" 67 "$(done_flag have_venv)"
  plan_disk "Reference repositories (references/)" 882 "$(done_flag have_references)"
  if have_client25; then plan_disk "2.5 client archive + extracted (.tools/legacy)" 1738 1
  else plan_disk "2.5 client archive + extracted (.tools/legacy)" $((1185 + 553 - $(size_of "$CLIENT25_ARCHIVE") / 1000000)) 0; fi
  if [ "$with80" = 1 ]; then
    if have_client80; then plan_disk "8.0 archive + data folder (.tools/legacy)" 3039 1
    else plan_disk "8.0 archive + data folder (.tools/legacy)" $((1824 + 1215 - $(size_of "$CLIENT80_ARCHIVE") / 1000000)) 0; fi
  fi
fi
plan_disk "Imported assets (client/assets/legacy)" 861 "$imported"
plan_disk "Godot import cache (client/.godot)" 916 "$godot_imported"
[ "$web" = 1 ] && plan_disk "Web build (build/web)" 1030 "$web_built"
free_kb=$(df -Pk . 2>/dev/null | awk 'NR == 2 { print $4 }')
printf '  %-48s %10s  (free: %s)\n' "Total new" "$(mb $((disk_total * 1000000)))" "$(mb $((${free_kb:-0} * 1000)))"
if [ "$import_only" = 0 ]; then
  archives=$CLIENT25_BYTES
  [ "$with80" = 1 ] && archives=$((archives + CLIENT80_BYTES))
  echo "  (After setup the client archives in .tools/legacy, $(mb "$archives"), may be deleted; keep them to re-extract.)"
fi
echo "  The imports need about 3 GB of free memory (the riding import peaks at 2.4 GB)."

if [ -n "$missing" ]; then
  echo
  echo "Missing required tools:$missing" >&2
  [ "$dry_run" = 1 ] && exit 0
  exit 1
fi
if [ "$import_only" = 0 ] && ! have_client25 && [ -z "$extractor" ]; then
  echo
  echo "No RAR extractor: install $(hint 'bsdtar (built in)' 'libarchive-tools (sudo apt install libarchive-tools)' '7-Zip (winget install 7zip.7zip), or use Windows 10+ tar.exe') and rerun." >&2
  [ "$dry_run" = 1 ] && exit 0
  exit 1
fi
if [ -n "${free_kb:-}" ] && [ $((disk_total * 1000)) -gt "$free_kb" ]; then
  echo "WARNING: this needs about $(mb $((disk_total * 1000000))) but only $(mb $((free_kb * 1000))) is free." >&2
fi
[ "$dry_run" = 1 ] && exit 0
if [ "$download_total" -gt 0 ] && [ "$yes" = 0 ]; then
  if [ -t 0 ]; then
    printf '\nDownload %s and continue? [y/N] ' "$(mb "$download_total")"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Nothing downloaded."; exit 1 ;; esac
  else
    echo "Not a terminal: rerun with --yes to download $(mb "$download_total")." >&2
    exit 1
  fi
fi

# ---- Downloads -----------------------------------------------------------------
download() {
  # download <url> <file> <bytes> [sha256]: resumable, checked by size and hash.
  mkdir -p "$(dirname "$2")"
  have=$(size_of "$2")
  if [ "$have" -gt "$3" ]; then
    echo "$2 is larger than expected; downloading it again."
    rm -f "$2"
  fi
  if [ "$(size_of "$2")" -ne "$3" ]; then
    curl -L --fail -C - --retry 5 --retry-delay 5 -o "$2" "$1"
  else
    echo "Already downloaded: $2"
  fi
  [ -z "${4:-}" ] && return
  actual=$(sha256_of "$2")
  if [ "$actual" != "$4" ]; then
    if [ "$(size_of "$2")" -eq "$3" ]; then
      echo "$2 has the right size but SHA-256 $actual, not $4: it is damaged. Delete it and rerun." >&2
      exit 1
    fi
    echo "WARNING: $2 has SHA-256 $actual, expected $4." >&2
    echo "  The upstream file changed. Imports may differ from the documented ones; check before relying on it." >&2
  fi
}

# Unzips with permissions (the Godot binaries must stay executable).
unzip_to() {
  "$PYTHON" - "$1" "$2" <<'EOF'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for info in archive.infolist():
        path = archive.extract(info, sys.argv[2])
        mode = info.external_attr >> 16
        if mode & 0o111:
            os.chmod(path, os.stat(path).st_mode | 0o111)
EOF
}

if [ "$import_only" = 0 ]; then
  step "Godot $GODOT_VERSION"
  if have_godot; then
    echo "Found: $(find_godot)"
  elif [ -n "$godot_asset" ]; then
    archive=".tools/downloads/Godot_v${GODOT_VERSION}_$godot_asset"
    download "$GODOT_RELEASE/Godot_v${GODOT_VERSION}_$godot_asset" "$archive" "$godot_bytes"
    if [ "$platform" = macos ]; then
      # ditto keeps the app bundle's symlinks and signature intact.
      ditto -x -k "$archive" .tools
    else
      mkdir -p .tools/godot
      unzip_to "$archive" .tools/godot
    fi
    rm -f "$archive"
    have_godot || { echo "Godot was not found at $godot_binary after unpacking." >&2; exit 1; }
    echo "Installed $godot_binary"
  else
    echo "Install Godot $GODOT_VERSION and put it on PATH as 'godot' (or set GODOT_BIN), then rerun." >&2
    exit 1
  fi

  if [ "$web" = 1 ]; then
    step "Godot web export templates"
    if have_templates; then
      echo "Found: $templates"
    else
      mkdir -p "$templates"
      status=0
      "$PYTHON" tools/fetch_zip_members.py "$TEMPLATES_URL" "$(native_path "$templates")" \
        templates/web_release.zip templates/web_debug.zip 'templates/web_nothreads_*.zip' templates/version.txt || status=$?
      if [ "$status" = 3 ]; then
        echo "The server refused partial downloads; fetching the whole archive ($(mb "$TEMPLATES_BYTES"))."
        download "$TEMPLATES_URL" .tools/downloads/export_templates.tpz "$TEMPLATES_BYTES"
        "$PYTHON" - .tools/downloads/export_templates.tpz "$(native_path "$templates")" <<'EOF'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for name in archive.namelist():
        if name.startswith('templates/web_') or name == 'templates/version.txt':
            with archive.open(name) as source, open(os.path.join(sys.argv[2], os.path.basename(name)), 'wb') as target:
                target.write(source.read())
EOF
        rm -f .tools/downloads/export_templates.tpz
      elif [ "$status" != 0 ]; then
        exit "$status"
      fi
      echo "Installed web templates into $templates"
    fi
  fi

  step "Python tools"
  if ! have_venv; then
    "$PYTHON" -m venv .tools/asset-venv || {
      echo "Could not create the venv$(hint '' ' (Debian/Ubuntu: sudo apt install python3-venv)' '')." >&2; exit 1; }
  fi
  "$(venv_python)" -m pip install --quiet --disable-pip-version-check -r tools/requirements.txt
  # Music is encoded to Ogg Vorbis with the soundfile package (tools/music_codec.py);
  # ffmpeg is only a fallback, and without either the tracks stay WAV.

  step "Reference repositories"
  "$PYTHON" - <<'EOF'
import json, subprocess, os
manifest = json.load(open('docs/reverse-engineering/local-references.json', encoding='utf-8'))
for repo in manifest['repositories']:
    checkout, head = repo['checkout'], repo['head']
    if not os.path.isdir(os.path.join(checkout, '.git')):
        bundle = repo.get('bundle', '')
        source = bundle if bundle and os.path.exists(bundle) else repo['repository']
        print(f'Cloning {source} -> {checkout}')
        # Deep Chinese paths: allow Windows paths over 260 characters.
        subprocess.run(['git', '-c', 'core.longpaths=true', 'clone', '--quiet', source, checkout], check=True)
        subprocess.run(['git', 'config', 'core.longpaths', 'true'], cwd=checkout, check=True)
    actual = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=checkout, capture_output=True, text=True, check=True).stdout.strip()
    if actual != head:
        subprocess.run(['git', 'checkout', '--quiet', head], cwd=checkout, check=True)
    print(f'{checkout} at {head[:12]}')
EOF

  step "StoneAge 2.5 client ($(mb "$CLIENT25_BYTES") download)"
  if have_client25; then
    echo "Found: $CLIENT25"
  else
    download "$CLIENT25_URL" "$CLIENT25_ARCHIVE" "$CLIENT25_BYTES" "$CLIENT25_SHA256"
    # Only the game folder (the archive also holds a third-party bot tool),
    # without executables, into a staging folder moved into place when complete.
    staging=.tools/legacy/extracted/.partial-2.5
    rm -rf "$staging"
    mkdir -p "$staging"
    echo "Extracting with $extractor"
    case "$extractor" in
      *7z|*7zz|*7za|*7z.exe)
        "$extractor" x -y -bd -o"$staging" "$CLIENT25_ARCHIVE" 'SA2.5-20260823/SA2.5/stoneage2.5/*' \
          -xr'!*.exe' -xr'!*.EXE' -xr'!*.dll' -xr'!*.DLL' -xr'!*.ocx' -xr'!*.OCX' -xr'!*.bat' -xr'!*.BAT' -xr'!*.scr' >/dev/null ;;
      *)
        "$extractor" -xf "$CLIENT25_ARCHIVE" -C "$staging" \
          --exclude '*.exe' --exclude '*.EXE' --exclude '*.dll' --exclude '*.DLL' \
          --exclude '*.ocx' --exclude '*.OCX' --exclude '*.bat' --exclude '*.BAT' --exclude '*.scr' \
          SA2.5-20260823/SA2.5/stoneage2.5 ;;
    esac
    [ -f "$staging/SA2.5-20260823/SA2.5/stoneage2.5/data/adrn_15.bin" ] || { echo "Unexpected archive layout: data/adrn_15.bin not found." >&2; exit 1; }
    mkdir -p "$(dirname "$CLIENT25")"
    rm -rf "$CLIENT25"
    mv "$staging/SA2.5-20260823/SA2.5/stoneage2.5" "$CLIENT25"
    rm -rf "$staging"
  fi

  if [ "$with80" = 1 ]; then
    step "StoneAge 8.0 client data ($(mb "$CLIENT80_BYTES") download, data folder only)"
    if have_client80; then
      echo "Found: $CLIENT80"
    else
      download "$CLIENT80_URL" "$CLIENT80_ARCHIVE" "$CLIENT80_BYTES" "$CLIENT80_SHA256"
      # Entry names are GBK; extract only data/, never the executables beside it.
      rm -rf "$CLIENT80.partial"
      "$PYTHON" - "$CLIENT80_ARCHIVE" "$CLIENT80.partial" <<'EOF'
import os, shutil, sys, zipfile
archive, dest = sys.argv[1], sys.argv[2]
blocked = ('.exe', '.dll', '.ocx', '.bat', '.cmd', '.vbs', '.scr')
count = 0
with zipfile.ZipFile(archive) as z:
    for info in z.infolist():
        name = info.filename
        if not info.flag_bits & 0x800:
            try:
                name = name.encode('cp437').decode('gbk')
            except UnicodeError:
                pass
        if '/data/' not in name or name.endswith('/') or name.lower().endswith(blocked):
            continue
        out = os.path.join(dest, 'data', name.split('/data/', 1)[1])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with z.open(info) as source, open(out, 'wb') as target:
            shutil.copyfileobj(source, target, 1 << 20)
        count += 1
print(f'Extracted {count} data files to {dest}')
EOF
      rm -rf "$CLIENT80"
      mv "$CLIENT80.partial" "$CLIENT80"
    fi
  fi
fi

PY=$(venv_python)
[ -n "$PY" ] || { echo "No Python tools in .tools/asset-venv; run without --import-only first." >&2; exit 1; }
have_client25 || { echo "No 2.5 client at $CLIENT25; run without --import-only first." >&2; exit 1; }
[ -d "$SERVER/gmsv" ] || { echo "No server reference at $SERVER; run without --import-only first." >&2; exit 1; }
extra=""
if [ "$with80" = 1 ]; then
  have_client80 || { echo "No 8.0 data at $CLIENT80; run without --import-only first, or add --no-8.0." >&2; exit 1; }
  extra="--extra-source $CLIENT80"
fi

# The imports are redone when an importer or the 8.0 choice changed since the
# last complete import (or always with --import-only).
import_key=$("$PY" - "$with80" <<'EOF'
import hashlib, pathlib, sys
digest = hashlib.sha256(sys.argv[1].encode())
for path in sorted(pathlib.Path('tools').glob('*.py')):
    if not path.name.startswith('test_'):
        digest.update(path.name.encode() + path.read_bytes())
print(digest.hexdigest())
EOF
)
if [ "$import_only" = 0 ] && [ -d client/assets/legacy/battle ] && [ -f "$IMPORT_STAMP" ] && [ "$(cat "$IMPORT_STAMP")" = "$import_key" ]; then
  step "Original resources already imported (use --import-only to import again)"
else
  step "Importing original resources (several minutes)"
  rm -f "$IMPORT_STAMP"
  run() { echo "-- $*"; "$@"; }
  run "$PY" tools/import_legacy.py "$CLIENT25" --server-map "$SERVER/gmsv/data/map/sainasu/samugiru/samugiru"
  run "$PY" tools/import_ui.py "$CLIENT25"
  run "$PY" tools/import_npc.py "$CLIENT25" "$SERVER/gmsv/data/npc"
  run "$PY" tools/import_wilderness.py "$CLIENT25" --server-map "$SERVER/gmsv/data/map/sainasu/sainasu"
  run "$PY" tools/import_battle.py "$CLIENT25"
  run "$PY" tools/import_battle_backgrounds.py "$CLIENT25"
  run "$PY" tools/import_mvp.py "$CLIENT25"
  run "$PY" tools/import_world.py "$CLIENT25"
  run "$PY" tools/import_early_quests.py "$CLIENT25" --reference "$SERVER"
  run "$PY" tools/import_pet_training.py "$CLIENT25"
  run "$PY" tools/import_characters.py "$CLIENT25"
  run "$PY" tools/import_faces.py "$CLIENT25"
  run "$PY" tools/import_pets.py "$CLIENT25"
  run "$PY" tools/import_mirror.py "$CLIENT25"
  run "$PY" tools/import_loading.py "$CLIENT25"
  # The radio takes the 8.0 soundtrack (26 tracks) when it is used, else 2.5's 24.
  if [ "$with80" = 1 ]; then run "$PY" tools/import_music.py "$CLIENT80"; else run "$PY" tools/import_music.py "$CLIENT25"; fi
  # With the 8.0 data the riding import adds the certificate mounts only 8.0 has.
  # shellcheck disable=SC2086
  run "$PY" tools/import_riding.py "$CLIENT25" $extra
  run "$PY" tools/import_grid_cursor.py "$CLIENT25"
  run "$PY" tools/import_cursor.py "$CLIENT_SOURCE/石器时代8.5客户端最新源代码/石器源码/123.cur"
  run "$PY" tools/import_encounters.py
  # Every pet template's battle sprite; with the 8.0 data also the 313 only 8.0 has (机豹, 黑乌力王, the album pets).
  # shellcheck disable=SC2086
  run "$PY" tools/import_encounter_art.py "$CLIENT25" $extra
  # After every sprite importer: each frame's original sound effect and hit sound.
  run "$PY" tools/import_battle_sounds.py "$CLIENT25" --table "$CLIENT_SOURCE/石器时代8.5客户端最新源代码/石器源码/systeminc/sndcnf.h"
  # Packs the per-frame PNGs the importers above wrote into sprite sheets.
  run "$PY" tools/pack_frame_sheets.py
  # Map tiles and props share one 256-colour palette (palette textures).
  run "$PY" tools/palette_images.py
  # Last: the small per-sprite files and indexes the game reads, from the
  # importers' manifests (the importers above also refresh their own).
  run python3 tools/split_manifests.py
  # 宠物大全's pre-cut thumbnails, from the sheets above.
  run "$PY" tools/build_pet_thumbs.py
  echo "$import_key" > "$IMPORT_STAMP"
fi

step "本机极速模式 helper for the pet hunt"
./scripts/build-fast-hunt.sh

step "Godot asset import (the first run takes about half an hour)"
./scripts/run.sh --headless --editor --import --quit >/dev/null 2>&1

if [ "$web" = 1 ]; then
  step "Web client"
  # shellcheck disable=SC3013 # -nt: dash, bash, busybox and Git Bash all have it
  if [ -f build/web/packs/packs.json ] && [ build/web/packs/packs.json -nt "$IMPORT_STAMP" ]; then
    echo "Found: build/web (after code changes rebuild it with ./scripts/build-web.sh)"
  elif ! have_templates; then
    echo "No web export templates in $templates; rerun without --import-only." >&2
    exit 1
  else
    ./scripts/build-web.sh
  fi
fi

step "Done"
echo "Play:        ./scripts/run.sh"
echo "Tests:       ./scripts/test-all.sh"
if [ "$web" = 1 ]; then echo "Web client:  ./scripts/serve.sh, then open the address it prints"; fi
exit 0
