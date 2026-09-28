#!/bin/sh
# Run every Godot suite in parallel without stopping at the first failure.
# Prints one PASS/FAIL line per suite with its time, then the slowest suites;
# logs land in $STONE_AGE_TEST_LOGS (default: a fresh temporary folder).
# $STONE_AGE_TEST_JOBS sets parallelism. Name suites to run only those.
# Exit status is non-zero if any suite failed. See tools/run_suites.py.
set -eu
cd "$(dirname "$0")/.."
exec python3 tools/run_suites.py "$@"
