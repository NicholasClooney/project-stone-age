# Hunt status coalescing: reproducible Web measurements

The authority still performs every encounter, queue comparison and uncaught
record. Only progress snapshots and uncaught-record refresh notifications are
merged. Stops, pauses, settings and battle transitions bypass progress throttling.
Queue overflow/threshold removals have a cumulative ticker summary per species;
individual reasons and beaters remain in the release log.

## Workload and measurement

Measured on 2026-10-02, Apple M4 Max, 14 CPU cores, 36 GiB RAM; Godot
4.6-stable and headless Chromium 153.0.8010.12. The actual exported game runs at
390×844 CSS pixels, DPR 1. This is a desktop browser with a phone viewport,
not a measurement on an Android/iPhone or Safari. No graphical window is opened.

Baseline: `3f749c0`, including the helper process reaping fix. Modified code:
`perf/hunt-status-throttle`. Each alternating run uses a fresh test Backend and
Web browser, original encounter data at map 100, cell (637,493), run seed 424242,
600 scheduled steps and ten real `scan_once()` calls per step. All runs produced
6000 rolls, 5008 inspected candidates, 5002 uncaught records and **identical final
queues**. The real queue/pruning/filter/projection/release code runs unchanged.
The harness holds `flow_step` at the hunt phase to isolate queue churn; it does
not exercise capture or training playback, or the native helper's throughput.
Parity and full capture behavior are covered separately by targeted suites.

Before timing, the actual 最小化 button is clicked and all queued asset downloads
finish. Chromium's `Network.webSocketFrameReceived` measures delivered UTF-8
status bytes, and `Performance.getMetrics().TaskDuration` measures the browser's
main-thread task time. Startup, screenshots and post-measurement records-page
interactions are excluded. Backend event instrumentation encodes each status
once more to count **emitted** bytes; its timed `core_usec` is instrumented elapsed
work time, **not native CPU time**. Client numbers below are actual Web numbers.

There was concurrent activity: the live server/native hunt and the parent's
full test run. A sample load average was 8.53/7.80/7.46; a sample process list
showed the live helper at 173.8% CPU and `fast_hunt_test` at 87.7%. Workload and
asset-loading state are controlled; machine contention is not. Do not interpret
these runs as a stable CPU improvement percentage.

## Three alternating runs

| Revision/run | Measured seconds | Received status messages | Status Hz | Received status bytes/s | Main-thread task ms/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before 1 | 10.352 | 4405 | 425.532 | 2,769,997.6 | 836.14 |
| After 1 | 10.040 | 10 | 0.996 | 4,271.2 | 592.94 |
| Before 2 | 15.042 | 5288 | 351.540 | 2,286,990.6 | 879.50 |
| After 2 | 13.021 | 13 | 0.998 | 4,236.0 | 837.30 |
| Before 3 | 23.324 | 9099 | 390.119 | 2,541,629.2 | 888.83 |
| After 3 | 13.481 | 14 | 1.039 | 4,432.4 | 851.14 |

The baseline generated 10,610 status messages and approximately 69.16 MB in every
run. Its outbound WebSocket queue filled and closed the client connection;
received counts therefore differ from emitted counts. The client reconnected
and resynchronized through real snapshots. The modified runs generated 10, 13
and 14 messages (42,884 / 55,159 / 59,751 bytes). Progress messages stay at most
one per second; exceptional state transitions are intentionally immediate.
The robust result is reduced traffic and avoided progress backlog. Main-thread
task time varies widely and the measured ranges overlap.

The repository runner was then exercised once more against the final server
changes: before 4597 received messages / 29,911,097 bytes over 10.042 s
(457.786 Hz, 2,978,657.0 bytes/s, 829.92 task ms/s); after 11 / 45,943 bytes
over 10.032 s (1.096 Hz averaged across endpoints, 4,579.6 bytes/s,
590.23 task ms/s). The extra final pending flush can appear at the sample
boundary: progress **send intervals** are at least 1000 ms, rather than a
promise of exactly ten messages in an arbitrary ten-second observation.
Both clients successfully opened 排队 and 放生 → 只看未捕获 through actual
canvas clicks and issued the corresponding authority requests. The exact raw
results and screenshots are in `/private/tmp/hunt-final-comparison/`.

Raw artifacts (kept outside Git) are `/private/tmp/hunt-web-{before,after}-{1,2,3}.json`,
matching `.backend.json` / `.backend.log`, and `.png` screenshots.
`/private/tmp/hunt-web-measurements.json` collects precise results. The first
unaccepted experiments had an incorrect start location or used Escape (which
stops the hunt); none of their data is included above.

## Reproduction

Create a separate baseline checkout, copy the imported assets/tooling with APFS
clones following AGENTS.md, and export both Web builds with `scripts/build-web.sh`.
Serve each build on **private** localhost ports, for example:

```sh
# In the respective checkouts; keep these background services running.
python3 tools/serve_web.py --bind 127.0.0.1 --port 18990
python3 tools/serve_web.py --bind 127.0.0.1 --port 18980

# In the modified checkout. Playwright and browser live in an external scratch directory.
python3 tools/hunt_status_compare.py \
  --baseline /private/tmp/sa-hunt-status-baseline \
  --modules /path/to/playwright-installation \
  --chrome '/path/to/Google Chrome for Testing' \
  --before-url http://127.0.0.1:18990 \
  --after-url http://127.0.0.1:18980 \
  --out /private/tmp/hunt-comparison --runs 3
```

The comparison runner copies the identical probe script into the baseline's
`client/tools`, uses ephemeral WebSocket ports and isolated test user directories,
and terminates only its own test-server child processes. It writes machine/load
metadata, raw results and screenshots. Never point it at the live server or real
save. The JS probe rejects any run without exactly 6000 rolls, and verifies real
`hunt_queue` and `pet_log(kind=released, uncaught=true)` requests after clicking
through the small-screen records controls.
