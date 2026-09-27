# Pet hunt throughput verification

Measured on local macOS arm64, Godot 4.6 stable, headless with Dummy audio. No foreground windows or player saves. These are short local measurements, not FPS or minimum-throughput guarantees.

## Reproduce

```sh
./scripts/run.sh --script res://tests/pet_hunt_benchmark.gd
```

Results: `/tmp/stone-age-pet-hunt-benchmark.json`. The harness manually paces frames against a monotonic wall clock at 60 Hz, warms up 30 real batches, then samples 2 seconds per rate, three repetitions. Workloads are Samgir wilderness `(100,637,493)` and Giru `(300,509,93)`; Giru inspects more capturable actors. It executes real encounter RNG, full troop generation and quality evaluation. A **test-only impossible quality cutoff of +9** prevents early matches; the UI does not permit this cutoff. The benchmark also disables the Lv.1 filter for a heavier quality-check workload. No original enemy probabilities, stats or RNG calls are changed.

## Measurements

Throughput is mean of three runs, with min–max shown. p50 is the mean of run medians; p95/p99 are the worst run percentile. Max is worst measured `_process` duration, including scheduler interruptions. Stop measures only synchronous stop-handler execution, **not end-to-end input latency**. Approximately 99.2% of a requested target is expected from the initial empty tick and finite 2-second window.

| Workload | Requested groups/s | Achieved mean (range) | p50 ms | p95 ms | p99 ms | Max ms | Stop handler ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| samgir | 500 | 496 (496–496) | 1.45 | 2.25 | 2.78 | 2.79 | 0.112 |
| samgir | 1000 | 991 (991–991) | 2.34 | 3.47 | 4.09 | 4.11 | 0.086 |
| samgir | 1500 | 1488 (1487–1489) | 3.24 | 4.15 | 4.34 | 4.45 | 0.158 |
| samgir | 2000 | 1980 (1975–1982) | 3.87 | 4.17 | 4.28 | 9.92 | 0.107 |
| giru | 500 | 496 (495–496) | 2.12 | 3.59 | 4.60 | 6.77 | 0.143 |
| giru | 1000 | 990 (988–992) | 3.42 | 4.31 | 4.38 | 5.50 | 0.084 |
| giru | 1500 | 1369 (1315–1447) | 4.10 | 4.29 | 4.35 | 4.64 | 0.085 |
| giru | 2000 | 1896 (1740–1983) | 3.68 | 4.25 | 4.36 | 4.92 | 0.092 |

Giru's non-monotonic results across requested rates reflect short samples and variable local CPU scheduling; do not infer that requesting 2,000 inherently makes each scan cheaper. Render cost and real event-loop input latency are excluded. The 9.92 ms outlier demonstrates why the work budget is soft, not a frame-time guarantee.

## Change and safety

- UI target range: 1–100,000 groups/s; default was 100 at measurement time (later changed to 3,000; measurements below remain historical). Requested speed is not a promise. UI displays achieved session-average wall-clock throughput.
- Preserve the 4,000 μs per-frame soft work budget, checked between complete scans. One scan and status formatting can overrun it; no running scan is interrupted. Backlog is capped at 100 ms of requested work, avoiding unbounded catch-up after stalls.
- Remove the old 20-credit cap, which independently limited 60 Hz execution to 1,200 groups/s.
- Prepare the already validated encounter area once per hunt. Original full catalog had 665 spatial areas; previously every roll searched them again. A run-local catalog keeps only this area while sharing immutable enemy/group/template definitions. Original generator, probabilities and RNG sequence are unchanged.
- Location changes cancel before another scan; restarting prepares the current area again. Runtime catalog hot-reloading is not implemented.
- Before spatial preparation, the same uncapped scheduler averaged 772/s (Samgir) and 633/s (Giru) at requested 2,000/s. Raw before/after samples are retained in `pet-hunt-performance-results.json`; variable machine load means these are observations, not controlled speedup ratios.

## Regression coverage

`pet_hunt_speed_test.gd`: higher target/default, 100 exact troop and RNG-state comparisons between original and prepared catalogs, real work, bounded backlog, target/actual UI, cancellation, location invalidation and restart. `pet_hunt_ui_test.gd` retains exact matched-individual battle handoff and no-reward/no-auto-capture checks.
