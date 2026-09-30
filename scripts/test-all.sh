#!/bin/sh
# Run every Godot suite in parallel without stopping at the first failure.
# Prints one PASS/FAIL line per suite with its time, then the slowest suites;
# logs land in $STONE_AGE_TEST_LOGS (default: a fresh temporary folder).
# $STONE_AGE_TEST_JOBS sets parallelism. Name suites (or --only a,b,c) to run
# only those. Each suite gets its own user:// folder, never the real one.
# Exit status is non-zero if any suite failed. See tools/run_suites.py.
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
require_python
exec "$PYTHON" tools/run_suites.py "$@"
