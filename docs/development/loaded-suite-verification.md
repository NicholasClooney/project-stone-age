# Loaded suite verification

These are fixture and waiting corrections, not gameplay changes. The four suites continue to use the original encounter catalog, real battle/forecast cores and real session authority. Remote minimize still runs two clients over a localhost WebSocket on port zero. No live server, real save, importer or foreground game is involved.

## Clean mixed encounters

The old first-hit comparison drove `backend._process(0.016)`, which scans as many groups as fit a 12 ms budget before advancing the flow. `showcase:false` now disables background search/presentation/training; the flow still uses the showcase queue. Consequently `hunt_last_hit` is the latest scan hit, not necessarily the queued troop selected for capture.

A diagnostic with encounter seed 9002 and the original strong character scanned a fixed number of real groups, then called `flow_step()`:

| Groups scanned | Latest hit clean | Selected troop clean | Real pending troop mixed | Phase |
| --- | --- | --- | --- | --- |
| 129 | false | false | true | capture |
| 130 | false | false | true | capture |
| 160 | true | false | true | capture |
| 256 | true | false | true | capture |
| 512 | false | false | true | capture |

Thus the historical `phase capture:` failure can occur with a correctly opened mixed battle. The suite now drives one real `scan_once()` and `flow_step()` per condition wait, so the weak and strong fixtures compare the same first accepted roll. The original mixed-hit assertion remains; additional checks require an active real mixed battle, its pinned Lv.1 capture target, and exact source group/template/level/growth-seed identities in the authority's pending battle.

## Borrowed LAN training

The old LAN fixture left `training_pool_rng` randomized. A diagnostic replayed the unchanged member-identity interruption and restart with seeds 0–31 in separate real account folders. Seed 20 produced a completed forecast with 3/5 wins and reason `扬奇洛斯 体力达到停机线`; authority correctly paused without opening the battle. Seed 0 produced 5/5 wins and actual shared battle/XP settlement. The historical failing runs did not log their seeds, so seed 20 reproduces the failure mechanism, not their exact random draw.

The suite now tests both outcomes explicitly. The ordinary fresh fixture fixes encounter and pool seeds to 9, while existing explicit seed coverage remains. `training_outcome()` waits for a terminal outcome; `enter()` additionally requires an opened battle. Expected refusal assertions separately require no battle and the correct stop reason. The three pending-forecast loops now use bounded condition waits and require an actual pending forecast before changing member/clone/pet identity.

## Travel gate

The historical log failed `walking up to return guard opens original dialogue`, then the return destination. The old fixture advanced five manual physics ticks and checked after fixed process frames. Movement completion and `WorldTravel._process()` opening the dialogue are separate events, and deferred map transitions have their own completion state. The corrected suite waits for completed movement, empty route, selected return guard, visible dialogue/choice, and the destination cell with no transition in progress. It retains actual input clicks and permit checks. The old timing failure was not reproduced in isolation during this investigation; its log and missing completion conditions support this correction, not a claim of a newly reproduced product race.

## Remote minimize

The historical log explicitly found a qualifying Lv.1 凯比特 (+8) after two groups, then correctly stopped searching. A rate of two groups/second did not guarantee a persistent hunt.

The fixture selects original template 114 through the UI, all four offsets +2, total +8, GDScript scanning at rate 2, and encounter seed 22. A separate real backend receives the live backend's actual filter and verifies identical run seed and 4096 real nonmatching groups. The live backend is never replaced, paused or advanced by that verifier. Existing store/release/withdraw, second-device push, panel identity and reload checks remain. The suite requires actual live encounter-count growth and asserts that the socket checks stay within the verified prefix.

## Validation

- Original diagnostic suites: 4/4 pass with two parallel jobs; this did not disprove the intermittent failures.
- Deterministic probes: clean batch-dependent mismatch and LAN seed-20 refusal reproduced as above.
- Corrected suites: `clean_hunt_test`, `training_borrow_test`, `travel_gate_test`, `remote_minimize_test`, 4/4 pass with two jobs (12 seconds).
- Final four-job targeted run: 4/4 pass (13 seconds). The integrating parent runs the full suite once after landing; this worktree does not run the full suite.
- Headless verification checks control state and interaction, not rendered pixels.
