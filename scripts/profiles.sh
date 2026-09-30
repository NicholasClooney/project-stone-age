#!/bin/sh
# LAN profiles: one headless server per character, side by side on this Mac,
# plus one web server with the lobby (docs/development/lan-profiles.md).
#   scripts/profiles.sh start [--skip-build] [--no-tailscale]
#   scripts/profiles.sh stop
#   scripts/profiles.sh status
# The profiles come from profiles.json in the repository root (or the file in
# $STONE_AGE_PROFILES); copy scripts/profiles.example.json to start.
# start: removes old Tailscale forwards, builds the web client (unless
# --skip-build), stops whatever listens on the configured ports, starts the web
# server (with /lobby) and every profile's backend (logs in build/profiles/),
# waits until all ports answer and forwards them over Tailscale. It stays in
# the foreground: Ctrl-C stops every server (each saves as it exits) and
# removes the forwards. The single-player setup (scripts/relaunch.sh) is not
# affected unless profiles.json uses its ports.
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
require_python

command="${1:-}"
[ $# -gt 0 ] && shift
build=1
tailscale_wanted=1
for argument in "$@"; do
  case "$argument" in
    --skip-build) build=0 ;;
    --no-tailscale) tailscale_wanted=0 ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

config="${STONE_AGE_PROFILES:-profiles.json}"
if [ ! -f "$config" ]; then
  echo "No $config. Copy scripts/profiles.example.json to profiles.json and edit it." >&2
  exit 1
fi

# "web <port> <fast threads>" then one "<name> <port> <save>" line per profile; refuses
# duplicate names, ports or saves.
table=$("$PYTHON" - "$config" <<'PROFILES'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
web = int(data.get("web_port", 8780))
print("web", web, int(data.get("fast_threads", 0)))
seen = {"port": {web}, "name": set(), "save": set()}
for entry in data.get("profiles", []):
    name = str(entry["name"])
    port = int(entry["port"])
    save = str(entry.get("save") or f"user://{name}.json")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        sys.exit(f"Profile name {name!r}: use letters, digits, - or _ (the title can be Chinese).")
    if " " in save:
        sys.exit(f"Save path {save!r} must not contain spaces.")
    for key, value in (("name", name), ("port", port), ("save", save)):
        if value in seen[key]:
            sys.exit(f"Two profiles use the same {key}: {value}")
        seen[key].add(value)
    print(name, port, save)
PROFILES
)
web_port=$(printf '%s\n' "$table" | awk '$1=="web"{print $2}')
fast_threads=$(printf '%s\n' "$table" | awk '$1=="web"{print $3}')
threads_arg=""
# "fast_threads": N fixes the helper budget the profiles share (else 线程数).
[ "$fast_threads" -gt 0 ] && threads_arg="--fast-threads=$fast_threads"
profiles=$(printf '%s\n' "$table" | awk '$1!="web"')
ports="$web_port $(printf '%s\n' "$profiles" | awk '{printf "%s ", $2}')"

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

tailscale=""
if [ "$tailscale_wanted" = 1 ]; then
  if command -v tailscale >/dev/null 2>&1; then
    tailscale=tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    tailscale=/Applications/Tailscale.app/Contents/MacOS/Tailscale
  fi
fi

forwards_off() {
  [ -n "$tailscale" ] || return 0
  for port in $ports; do "$tailscale" serve --https="$port" off >/dev/null 2>&1 || true; done
}

# Every backend at once through scripts/stop-server.sh: it asks the server
# to save, write its restart-resume file and release its save lock (the
# server's --shutdown-file, build/server-<port>.shutdown), and sends TERM
# only if that does not work (a stale save lock is then taken over at the
# next start). Passing the backend port as --web-port too keeps it from
# touching the shared web server, which gets TERM afterwards.
stop_listeners() {
  stoppers=""
  for port in $(printf '%s\n' "$profiles" | awk '{print $2}'); do
    if listening "$port"; then
      ./scripts/stop-server.sh --port="$port" --web-port="$port" &
      stoppers="$stoppers $!"
    fi
  done
  for stopper in $stoppers; do wait "$stopper" || true; done
  # Without lsof (Git Bash) the web server started here is stopped with Ctrl-C instead.
  pids=$(lsof -tnP -iTCP:"$web_port" -sTCP:LISTEN 2>/dev/null || true)
  [ -n "$pids" ] && kill -TERM $pids 2>/dev/null || true
  # shellcheck disable=SC2086
  wait_for down 30 $ports
}

case "$command" in
  status)
    printf '%-14s %-6s %-8s %s\n' profile port state save
    printf '%-14s %-6s %-8s %s\n' "(web)" "$web_port" "$(listening "$web_port" && echo online || echo offline)" "/lobby"
    printf '%s\n' "$profiles" | while read -r name port save; do
      [ -n "$name" ] || continue
      printf '%-14s %-6s %-8s %s\n' "$name" "$port" "$(listening "$port" && echo online || echo offline)" "$save"
    done
    exit 0 ;;
  stop)
    echo "==> Stopping the profile servers on $ports"
    forwards_off
    stop_listeners || { echo "Some ports are still in use: $ports" >&2; exit 1; }
    exit 0 ;;
  start) ;;
  *)
    echo "Usage: scripts/profiles.sh start [--skip-build] [--no-tailscale] | stop | status" >&2
    exit 2 ;;
esac

if [ "$tailscale_wanted" = 1 ] && [ -z "$tailscale" ]; then
  echo "Tailscale CLI not found; serving on this network only (use --no-tailscale to silence this)." >&2
fi

if [ -n "$tailscale" ]; then
  echo "==> Removing Tailscale forwards on $ports"
  forwards_off
fi

if [ "$build" = 1 ]; then
  echo "==> Building the web client"
  ./scripts/build-web.sh
fi
./scripts/build-fast-hunt.sh --quiet || true

echo "==> Stopping servers on $ports"
stop_listeners || { echo "Ports are still in use: $ports" >&2; exit 1; }

# Certificates as in serve.sh: both the page and the backends use them.
tls=""
web_tls=""
if [ -z "${STONE_AGE_TLS_CERT:-}" ] && [ -f .tools/tls/cert.pem ] && [ -f .tools/tls/key.pem ]; then
  STONE_AGE_TLS_CERT=$(native_path "$PWD/.tools/tls/cert.pem")
  STONE_AGE_TLS_KEY=$(native_path "$PWD/.tools/tls/key.pem")
fi
if [ -n "${STONE_AGE_TLS_CERT:-}" ] && [ -n "${STONE_AGE_TLS_KEY:-}" ]; then
  tls="--tls-cert=$STONE_AGE_TLS_CERT --tls-key=$STONE_AGE_TLS_KEY"
  web_tls="--cert $STONE_AGE_TLS_CERT --key $STONE_AGE_TLS_KEY"
  scheme="https+insecure"
else
  echo "WARNING: no certificate in .tools/tls; serving plain HTTP / WS." >&2
  scheme="http"
fi

mkdir -p build/profiles
children=""
echo "==> Starting the web server with the lobby on $web_port"
# shellcheck disable=SC2086
"$PYTHON" tools/serve_web.py --port "$web_port" --profiles "$config" $web_tls > build/profiles/web.log 2>&1 &
children="$children $!"
printf '%s\n' "$profiles" | while read -r name port save; do
  [ -n "$name" ] || continue
  echo "==> Starting $name on $port ($save), log build/profiles/$name.log"
done
while read -r name port save; do
  [ -n "$name" ] || continue
  # shellcheck disable=SC2086
  ./scripts/run.sh --headless --script res://server/server_main.gd -- $tls $threads_arg "--shutdown-file=$(native_path "$PWD/build/server-$port.shutdown")" --port="$port" --save="$save" > "build/profiles/$name.log" 2>&1 &
  children="$children $!"
done <<EOF
$profiles
EOF

stop() {
  trap - INT TERM
  echo
  echo "==> Stopping: removing forwards and every profile server"
  forwards_off
  stop_listeners || true
  # shellcheck disable=SC2086
  kill -TERM $children 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap stop INT TERM

# shellcheck disable=SC2086
if ! wait_for up 90 $ports; then
  echo "Not every server started listening on $ports; see build/profiles/*.log." >&2
  stop
fi

name=""
if [ -n "$tailscale" ]; then
  echo "==> Forwarding over Tailscale"
  for port in $ports; do "$tailscale" serve --bg --https="$port" "$scheme://127.0.0.1:$port" >/dev/null; done
  name=$("$tailscale" status --json 2>/dev/null | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)
fi
page="https"
[ "$scheme" = http ] && page="http"
echo
echo "Lobby: $page://${name:-<this Mac>}:$web_port/lobby"
echo "Ctrl-C stops every profile server and removes the forwards."
wait || true
forwards_off
