#!/bin/sh
# Run every Godot suite in parallel without stopping at the first failure.
# Prints one PASS/FAIL line per suite; logs land in $STONE_AGE_TEST_LOGS
# (default: a fresh temporary folder). Exit status is non-zero if any suite failed.
set -eu
cd "$(dirname "$0")/.."
jobs="${STONE_AGE_TEST_JOBS:-6}"
logs="${STONE_AGE_TEST_LOGS:-$(mktemp -d -t stone-age-suites)}"
mkdir -p "$logs"
./scripts/run.sh --headless --editor --import --quit >/dev/null 2>&1
suites=$(sed -n 's/^for suite in \(.*\); do$/\1/p' scripts/test.sh)
export logs
printf '%s\n' $suites | xargs -P "$jobs" -n 1 sh -c '
  if timeout 300 ./scripts/run.sh --headless --script "res://tests/$1.gd" >"$logs/$1.log" 2>&1 \
     && ! grep -Eq "SCRIPT ERROR|^ERROR:|FAIL:" "$logs/$1.log"; then
    echo "PASS $1"
  else
    echo "FAIL $1"
  fi' _ | sort -k1,1r -k2 | tee "$logs/summary.txt"
echo "logs: $logs"
! grep -q '^FAIL' "$logs/summary.txt"
