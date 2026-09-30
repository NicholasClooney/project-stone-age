#!/bin/sh
# Rebuild and restart the game for play over Tailscale, in one step:
#   1. remove this Mac's Tailscale forwards for the web and backend ports
#   2. build the web client (scripts/build-web.sh; skip with --skip-build)
#   3. stop a running scripts/serve.sh (the backend saves as it exits)
#   4. start scripts/serve.sh and wait until both ports answer
#   5. forward https://<this Mac>.<tailnet>.ts.net:8780 and :8781 to it
# Stays in the foreground: Ctrl-C stops the server and removes the forwards.
# Any other arguments go to serve.sh (for example --save=user://try.json).
set -eu
cd "$(dirname "$0")/.."

web_port="${STONE_AGE_WEB_PORT:-8780}"
backend_port=8781
build=1
for argument in "$@"; do
  case "$argument" in
    --skip-build) build=0 ;;
    --port=*) backend_port="${argument#--port=}" ;;
  esac
done

# The Mac app's CLI is often only a shell alias, which scripts don't see.
if command -v tailscale >/dev/null 2>&1; then
  tailscale=tailscale
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
  tailscale=/Applications/Tailscale.app/Contents/MacOS/Tailscale
else
  echo "Tailscale CLI not found." >&2
  exit 1
fi

# serve.sh serves HTTPS when a certificate exists; Tailscale must match it.
if [ -f .tools/tls/cert.pem ] && [ -f .tools/tls/key.pem ]; then scheme="https+insecure"; else scheme="http"; fi

forwards_off() {
  "$tailscale" serve --https="$web_port" off >/dev/null 2>&1 || true
  "$tailscale" serve --https="$backend_port" off >/dev/null 2>&1 || true
}

listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

wait_for() {
  # wait_for <want: up|down> <seconds> <port>...
  want="$1"; seconds="$2"; shift 2
  while [ "$seconds" -gt 0 ]; do
    done_waiting=1
    for port in "$@"; do
      if [ "$want" = up ] && ! listening "$port"; then done_waiting=0; fi
      if [ "$want" = down ] && listening "$port"; then done_waiting=0; fi
    done
    [ "$done_waiting" = 1 ] && return 0
    sleep 1
    seconds=$((seconds-1))
  done
  return 1
}

echo "==> Removing Tailscale forwards on $web_port and $backend_port"
forwards_off

if [ "$build" = 1 ]; then
  echo "==> Building the web client"
  ./scripts/build-web.sh
fi

echo "==> Stopping the running server"
# Only what listens on these two ports (other servers, such as a test page on
# another port, keep running). TERM, not INT: a server started in the
# background ignores INT, and Godot quits cleanly on TERM (it saves and writes
# the restart-resume file in server_main.gd _finalize).
signal_listeners() {
  pids=$(lsof -tnP -iTCP:"$web_port" -iTCP:"$backend_port" -sTCP:LISTEN 2>/dev/null || true)
  [ -n "$pids" ] && kill "-$1" $pids 2>/dev/null || true
}
signal_listeners TERM
wait_for down 30 "$web_port" "$backend_port" || { echo "Ports $web_port/$backend_port are still in use." >&2; exit 1; }

echo "==> Starting the server"
# Arguments meant for this script are dropped; the rest go to the backend.
set -- $(for argument in "$@"; do [ "$argument" = --skip-build ] || printf '%s\n' "$argument"; done)
./scripts/serve.sh "$@" &
server=$!

stop() {
  trap - INT TERM
  echo
  echo "==> Stopping: removing forwards and the server"
  forwards_off
  # The backend itself, so it quits cleanly and saves (see signal_listeners).
  signal_listeners TERM
  wait_for down 30 "$web_port" "$backend_port" || true
  kill -TERM "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  exit 0
}
trap stop INT TERM

if ! wait_for up 60 "$web_port" "$backend_port"; then
  echo "The server did not start listening on $web_port and $backend_port." >&2
  stop
fi

echo "==> Forwarding over Tailscale"
"$tailscale" serve --bg --https="$web_port" "$scheme://127.0.0.1:$web_port" >/dev/null
"$tailscale" serve --bg --https="$backend_port" "$scheme://127.0.0.1:$backend_port" >/dev/null
name=$("$tailscale" status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)
echo
echo "Ready: https://${name:-<this Mac>.<tailnet>.ts.net}:$web_port/"
echo "Ctrl-C stops the server and removes the forwards."
wait "$server" || true
forwards_off
