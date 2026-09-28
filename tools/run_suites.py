#!/usr/bin/env python3
"""Run the Godot test suites in parallel and report each one.

Suites come from the list in scripts/test.sh (or the command line). Each runs
in its own headless Godot with its output in <logs>/<suite>.log. A suite
passes when Godot exits 0 and the log has no script error, engine error or
FAIL line.

Two things keep a run short:
- A suite whose script fails to compile never quits on its own; it is killed
  as soon as the log shows the compile error instead of at the timeout. One
  whose log stops growing for STALL seconds after a script error is killed too.
- Durations from earlier runs are kept in build/test-durations.json and the
  slowest suites start first, so the run does not end on one long straggler.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DURATIONS = ROOT / "build" / "test-durations.json"
FAILURE = re.compile(r"SCRIPT ERROR|^ERROR:|FAIL:", re.M)
# Printed when a test script cannot load; Godot then idles until killed.
COMPILE_ERROR = re.compile(r"Failed to load script \"res://tests/|Parse Error:.*\n.*res://tests/")
TIMEOUT = 300
STALL = 30


def suites_from_test_sh():
    text = (ROOT / "scripts" / "test.sh").read_text()
    match = re.search(r"^for suite in (.*); do$", text, re.M)
    return match.group(1).split()


def load_durations():
    try:
        return json.loads(DURATIONS.read_text())
    except (OSError, ValueError):
        return {}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("suites", nargs="*", help="suite names (default: every suite in scripts/test.sh)")
    parser.add_argument("--jobs", type=int, default=int(os.environ.get("STONE_AGE_TEST_JOBS", "8")))
    parser.add_argument("--logs", default=os.environ.get("STONE_AGE_TEST_LOGS", ""))
    args = parser.parse_args()
    logs = Path(args.logs or tempfile.mkdtemp(prefix="stone-age-suites-"))
    logs.mkdir(parents=True, exist_ok=True)
    durations = load_durations()
    queue = sorted(args.suites or suites_from_test_sh(), key=lambda name: -durations.get(name, 60.0))

    subprocess.run(["./scripts/run.sh", "--headless", "--editor", "--import", "--quit"], cwd=ROOT,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    running = {}
    results = {}
    sizes = {}
    quiet_since = {}
    started = time.monotonic()
    while queue or running:
        while queue and len(running) < args.jobs:
            name = queue.pop(0)
            log = open(logs / f"{name}.log", "w")
            process = subprocess.Popen(["./scripts/run.sh", "--headless", "--script", f"res://tests/{name}.gd"],
                                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            running[name] = (process, log, time.monotonic())
        time.sleep(0.2)
        for name, (process, log, begun) in list(running.items()):
            elapsed = time.monotonic() - begun
            reason = ""
            if process.poll() is None:
                text = (logs / f"{name}.log").read_text(errors="replace")
                if len(text) != sizes.get(name):
                    sizes[name] = len(text)
                    quiet_since[name] = time.monotonic()
                if COMPILE_ERROR.search(text):
                    reason = "compile error"
                elif "SCRIPT ERROR" in text and time.monotonic() - quiet_since[name] > STALL:
                    # A runtime error usually leaves the test awaiting a signal forever.
                    reason = f"stalled {STALL} s after a script error"
                elif elapsed > TIMEOUT:
                    reason = f"timed out after {TIMEOUT} s"
                else:
                    continue
                process.kill()
                process.wait()
            log.close()
            del running[name]
            text = (logs / f"{name}.log").read_text(errors="replace")
            ok = not reason and process.returncode == 0 and not FAILURE.search(text)
            results[name] = (ok, elapsed, reason)
            durations[name] = round(elapsed, 1)
            print(f"{'PASS' if ok else 'FAIL'} {name} ({elapsed:.0f} s{', ' + reason if reason else ''})", flush=True)

    DURATIONS.parent.mkdir(exist_ok=True)
    DURATIONS.write_text(json.dumps(durations, indent=1, sort_keys=True) + "\n")
    failed = sorted(name for name, (ok, _, _) in results.items() if not ok)
    slowest = sorted(results.items(), key=lambda item: -item[1][1])[:5]
    summary = [f"{'FAIL' if name in failed else 'PASS'} {name}" for name in sorted(results)]
    (logs / "summary.txt").write_text("\n".join(summary) + "\n")
    print(f"\n{len(results) - len(failed)}/{len(results)} passed in {time.monotonic() - started:.0f} s with {args.jobs} jobs")
    print("slowest: " + ", ".join(f"{name} {seconds:.0f} s" for name, (_, seconds, _) in slowest))
    for name in failed:
        print(f"FAIL {name}: {logs / (name + '.log')}")
    print(f"logs: {logs}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
