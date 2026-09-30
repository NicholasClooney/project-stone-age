#!/bin/sh
# Stop a running scripts/serve.sh gracefully, so the backend records the stop,
# saves and writes the restart-resume file (<save>.resume.json):
#   1. create build/server-<backend port>.shutdown (serve.sh passes that path
#      to the backend as --shutdown-file); the backend quits within a second
#   2. wait up to 30 s for the backend and web ports to close
#   3. otherwise send TERM to what still listens there and wait 10 s more.
#      Godot does not save on TERM, but while a hunt, find-pet cycle or
#      自动练级 runs the backend keeps the resume file current (at every step
#      of the run, else every 10 s), so even TERM or kill -9 resumes from it.
# Options: --port=8781 (backend), --web-port=8780 (default STONE_AGE_WEB_PORT).
# Exits 0 once both ports are free, 1 if something still listens.
set -eu
cd "$(dirname "$0")/.."

web_port="${STONE_AGE_WEB_PORT:-8780}"
backend_port=8781
for argument in "$@"; do
  case "$argument" in
    --port=*) backend_port="${argument#--port=}" ;;
    --web-port=*) web_port="${argument#--web-port=}" ;;
  esac
done
request="build/server-$backend_port.shutdown"

listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

both_down() {
  ! listening "$web_port" && ! listening "$backend_port"
}

wait_down() {
  # wait_down <seconds>
  seconds="$1"
  while [ "$seconds" -gt 0 ]; do
    both_down && return 0
    sleep 1
    seconds=$((seconds-1))
  done
  both_down
}

if both_down; then
  rm -f "$request"
  echo "Nothing listens on $web_port or $backend_port."
  exit 0
fi

if listening "$backend_port"; then
  echo "==> Asking the backend on $backend_port to save and quit"
  mkdir -p build
  : > "$request"
fi
if wait_down 30; then
  rm -f "$request"
  echo "Stopped."
  exit 0
fi

rm -f "$request"
echo "The server did not quit on request; sending TERM (a running hunt resumes from its periodic resume file)." >&2
pids=$(lsof -tnP -iTCP:"$web_port" -iTCP:"$backend_port" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$pids" ]; then kill -TERM $pids 2>/dev/null || true; fi
if wait_down 10; then
  echo "Stopped with TERM."
  exit 0
fi
echo "Ports $web_port/$backend_port are still in use." >&2
exit 1
