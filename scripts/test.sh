#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/run.sh --headless --editor --import --quit
log_file=$(mktemp -t stone-age-tests)
trap 'rm -f "$log_file"' EXIT
for suite in smoke npc_smoke ui_smoke; do
if ./scripts/run.sh --headless --script "res://tests/$suite.gd" >"$log_file" 2>&1; then
  cat "$log_file"
else
  cat "$log_file"
  exit 1
fi
if grep -Eq 'SCRIPT ERROR|^ERROR:|FAIL:' "$log_file"; then
  echo 'Godot reported an error despite its process exit status.' >&2
  exit 1
fi
done
