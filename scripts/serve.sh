#!/bin/sh
# Run the headless backend that remote clients connect to, and, once
# scripts/build-web.sh has produced build/web, the web client on port 8780.
# Backend options: --port=8781 --bind=* --save=user://single-player.json
# Web options via environment: STONE_AGE_WEB_PORT (8780), STONE_AGE_TLS_CERT and
# STONE_AGE_TLS_KEY (serve both over TLS for a secure browser context).
# Stop with scripts/stop-server.sh (same --port): it asks the backend through
# build/server-<port>.shutdown to save, write the restart-resume file and quit.
# Ctrl-C in a terminal works too; a running hunt then resumes from the resume
# file the backend keeps current. Progress is saved after every settlement.
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
require_godot
require_python
# The pet hunt's 本机极速模式 helper; without a compiler the hunt scans in GDScript.
./scripts/build-fast-hunt.sh --quiet || true
tls=""
web_tls=""
# Certificates from scripts/make-cert.sh are used automatically.
if [ -z "${STONE_AGE_TLS_CERT:-}" ] && [ -f .tools/tls/cert.pem ] && [ -f .tools/tls/key.pem ]; then
  STONE_AGE_TLS_CERT=$(native_path "$PWD/.tools/tls/cert.pem")
  STONE_AGE_TLS_KEY=$(native_path "$PWD/.tools/tls/key.pem")
fi
if [ -n "${STONE_AGE_TLS_CERT:-}" ] && [ -n "${STONE_AGE_TLS_KEY:-}" ]; then
  tls="--tls-cert=$STONE_AGE_TLS_CERT --tls-key=$STONE_AGE_TLS_KEY"
  web_tls="--cert $STONE_AGE_TLS_CERT --key $STONE_AGE_TLS_KEY"
  echo "Serving HTTPS / WSS with $STONE_AGE_TLS_CERT"
else
  # Clients opened on https:// (or a desktop client given wss://) cannot talk
  # to a plain server: the page fails and the WebSocket hangs while connecting.
  # .tools/ is ignored, so every checkout or worktree needs its own copy.
  echo "WARNING: no certificate in .tools/tls; serving plain HTTP / WS." >&2
  echo "  Use http:// and ws:// URLs, or run scripts/make-cert.sh (or copy .tools/tls from another checkout)." >&2
fi
if [ -f build/web/index.html ]; then
  # shellcheck disable=SC2086
  "$PYTHON" tools/serve_web.py --port "${STONE_AGE_WEB_PORT:-8780}" $web_tls &
  web_pid=$!
  trap 'kill "$web_pid" 2>/dev/null' EXIT INT TERM
fi
backend_port=8781
for argument in "$@"; do
  case "$argument" in --port=*) backend_port="${argument#--port=}" ;; esac
done
mkdir -p build
shutdown_file=$(native_path "$PWD/build/server-$backend_port.shutdown")
# shellcheck disable=SC2086
"$engine" --headless --path client --audio-driver Dummy --script res://server/server_main.gd -- $tls "--shutdown-file=$shutdown_file" "$@"
