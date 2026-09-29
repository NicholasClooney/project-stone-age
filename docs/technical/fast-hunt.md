# Fast hunt (本机极速模式)

The pet hunt (`client/server/automation.gd`, `scan_once`) rolls wild troops at the character's cell and checks each newborn's hidden grades and, in a find-pet cycle, its exact Lv120 stats. In GDScript that is about 19,000 rolls a second; a Lv120 blue dragon with a stat sum of 625 needs about 4.6 billion rolls. The fast hunt runs the same scan in a native helper on every CPU core but one, at about 72 million rolls a second on a 14-core Mac. Player-facing numbers are in [pet-hunt-helper.md](../development/pet-hunt-helper.md).

## Pieces

| Piece | Role |
| --- | --- |
| `tools/fast_hunt/fast_hunt.c` | C99 helper with pthreads, no dependencies. Scans rolls, reports progress and the first hit. |
| `scripts/build-fast-hunt.sh` | Builds `build/fast_hunt` with `cc -O2 -pthread` when missing or stale. Called by `run.sh`, `serve.sh` and `setup-original-data.sh`. Without a compiler it prints a note and exits 0. |
| `client/server/fast_hunt.gd` | Per-roll seed, availability, writing the helper's input, launching, polling and killing it. |
| `client/server/automation.gd` | `_fast_process()` drives the helper from the hunt tick; `roll_at`, `first_match` and `_scan_index` replay a roll in GDScript. |
| `hunt.fast` setting | Per character, default `true` (`client/data/automation_defaults.json`). |

## Independent rolls

The hunt used to draw every troop from the backend's shared `encounter_rng`, so roll N depended on all rolls before it and could not be split across cores. Now roll `i` of a run uses its own `RandomNumberGenerator` seeded with

    roll_seed(run_seed, i) = splitmix64(run_seed + (i + 1) * 0x9E3779B97F4A7C15)

`run_seed` is two draws from `encounter_rng` when the hunt starts, so tests that seed `encounter_rng` stay deterministic. Walking encounters still use `encounter_rng` directly. GDScript has only signed 64-bit integers and an arithmetic `>>`, so `FastHunt.roll_seed` masks each shift; the wrapping multiplication matches C (checked against the C output).

## Matching Godot exactly

The helper reimplements, for one roll:

- **Godot 4.6 `RandomPCG`:**
  - pcg32 with the default increment `1442695040888963407`, seeded by `pcg32_srandom_r`.
  - `randi()` is the next 32-bit output.
  - `randi_range(a, b)` is `bounded(|a - b| + 1) + min(a, b)` with modulo rejection (`threshold = -bound % bound`).
  - `randi_range(a, a)` returns `a` without a draw.

  These were confirmed by comparing sequences printed by Godot for many seeds and ranges; Lemire's method does not match.
- **`encounter_catalog.gd`:** `roll()` (weighted group, count, the up-to-100 attempts with `max_count`, multiplicity and the five-slot swap for large monsters) and `actor()` (level, four grade draws, ten birth points, `randi()` growth seed, base stats with integer wild growth).
- **`scan_once`'s filters and `HuntRules.matches`:** capturable, usable template, target template, Lv1, grade total and per-grade minimums.
- **During a find-pet cycle, `accepts_prediction`:** `Progression.project_pet` to Lv120 (per-level seed `growth_seed + level * 104729`, ten points, roll `450 + rank * 20 .. + 50`, integer division) and `StatFilter.evaluate`. It also tracks the best prediction and the number of rejected predictions.

`fast_hunt_test` compares C and GDScript roll by roll: about 18,000 rolls and 45,000 enemies. It checks troops, levels, grades, growth seeds, base stats, Lv120 stats and the slot the hunt takes, across four named spots and 60 random areas. `build/fast_hunt INPUT --roll FROM COUNT` prints rolls for that comparison.

## Protocol

`automation.gd` writes an input file under `user://fast-hunt/`. The file holds:

- the run seed, first roll and roll limit, and the thread count;
- the area's candidate groups, in the order and with the weights `roll()` uses;
- their enemies and templates;
- the hunt filter;
- whether predictions apply, and each usable template's stat filter.

It then starts `build/fast_hunt INPUT STATUS` with `OS.create_process`.

The helper splits rolls into chunks of 65,536 and hands them to worker threads. The main thread commits chunk results in order, so the reported first hit is the lowest roll index that hits, the same one the sequential scan finds. About ten times a second it atomically rewrites STATUS with one line:

    KIND INDEX SLOT INSPECTED BEST PRED_REJECTS BEST_SUM BEST_ATTACK

`KIND` is one of:
- `progress`: the next roll to commit.
- `hit`: roll `INDEX` is taken at enemy `SLOT`.
- `stop`: roll `INDEX` gives an empty troop.
- `limit`: the roll limit was reached.

The counters always cover rolls before `INDEX`, so the backend's status shows the same numbers the GDScript scan would.

The backend polls STATUS every 100 ms from the hunt tick and never blocks a frame. On `hit` or `stop` it sets its counters and calls `_scan_index(INDEX, expected)`, which rolls that index again in GDScript. Only if the replay gives the same outcome does the hunt continue on the ordinary path (battle, capture, training, workflow). Any difference stops the hunt with 本机极速模式的结果与游戏复核不一致 and opens no battle; `fast_hunt_flow_test` checks this with a fake helper that lies.

## Thread count (线程数)

The number of worker threads belongs to the server's computer, not to a character, so it is not in the profile or a client's `viewer.cfg`:
- **Stored** by the backend in `user://server-settings.cfg` (`client/server/server_settings.gd`, section `fast_hunt`, key `threads`). 0 means automatic: the helper uses all cores but one (one core on a machine with two or fewer).
- **Changed** with the backend command `set_fast_hunt_threads` (`threads`: an integer from 0 to `OS.get_processor_count()`; a whole JSON number is accepted, anything else is rejected with a reason). It works over the WebSocket like every command.
- **Published** in the automation status as `hunt.threads` (the setting), `hunt.threads_used` (what the helper runs with) and `hunt.cores`, so every device's 自动抓极品 window shows the same value and the server's core count (本机 N 核).
- **Applied at once.** A change stops a running helper; the next hunt tick starts it again from the committed roll index with the new count. Rolls are committed in order and every roll has its own seed, so nothing is skipped or counted twice.
- **Input.** The count reaches the helper as the `threads` line of INPUT. `FastHunt.threads` remains a cap for tests (suites running side by side keep it small); the game leaves it at 0.

## When it runs, and when not

- It runs only when all of these hold:
  - `hunt.fast` is on and `hunt.rate` is 0 (不限速). A positive rate asks for a throttled scan, which stays in GDScript.
  - The backend's computer can run the helper. `FastHunt.unavailable_reason()` is empty on macOS or Linux when `build/fast_hunt` exists; the web build and Windows fall back.
  - The hunt uses the real encounter catalog. Tests that swap in a fixture catalog stay in GDScript.
- The helper starts lazily from the hunt tick. A direct `scan_once()` (the test seam) stops a running helper and continues in GDScript from the committed counters. This is safe because every roll is independent.
- If the helper cannot start or exits without a final report, the hunt switches to GDScript and the window says why.
- `stop_hunt` kills the helper. If the backend process itself goes away, the helper sees its parent change and exits.
- The hunt window shows 本机极速模式 or the reason for the ordinary scan, and the rolls per second. The checkbox is greyed, with the reason, when the backend cannot run the helper.

## Tests

- `fast_hunt_test`: C and GDScript agree roll by roll.
- `fast_hunt_flow_test`, on a backend:
  - Both modes hit the same roll, slot and pet with the same counters.
  - A find-pet cycle's prediction hands off to capture.
  - A missing helper falls back.
  - An unconfirmed hit stops the hunt.
- `pet_hunt_ui_test`: the checkbox is on by default, is saved with the character, and is greyed without the helper.
- `fast_hunt_threads_test`: 线程数 validation, the server-side file, the status fields, nothing stored with the character, a running helper restarting with the new count (read from its INPUT) without losing rolls, and two remote devices sharing the value, with an invalid value rejected.
- Suites that measure the GDScript scan (`pet_hunt_speed_test`) turn fast mode off. Remote tests that need a slow hunt set a rate, which keeps them in GDScript.
