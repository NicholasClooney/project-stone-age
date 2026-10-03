# Full195 golden Bui walking regression

Base: `integrate/stage-three` at `c8728ba3`. This correction changes only the walking test and this note; no encounter rules, enabled quests, production code, deadlines or step limits change.

## Cause and reproduction

The former test used Backend's randomized encounter RNG and assumed a battle would open within 160 ordinary steps. Original areas 524/534/544 (maps 800/820/840, groups 708/709/710) have minimum pressure 1 and maximum 2. `EncounterCatalog.step` draws an integer from 0 through 119 and compares it with pressure. A miss increases pressure only up to 2. These areas have no event condition, and their original weighted groups remain in use.

Even with maximum pressure, 160 misses have probability `(118/120)^160`, approximately 6.794%. Starting at minimum pressure gives approximately 6.852%. Thus this was a randomized finite-input test, not a guarantee provided by walking or by the source encounter rules. Full195 and the reported historical full157 did not log their RNG seeds; this report does not claim to recover those exact random streams.

A diagnostic Backend subclass delegated every real WS command to `super.handle`, recording the command, reply, authoritative position, RNG state and pressure. An unseeded targeted run passed, which by itself does not resolve the failure. A second run pinned only `encounter_rng.seed=6` before map 820 and reproduced the original failure through the production GameScene/WS/GameAreas path: all 160 walks generated accepted `field_step` requests with `encounter=true`, all 160 advanced the original RNG, pressure remained 2, and all 160 returned `hit=false`. Position reports were accepted and the connection stayed online. No battle was forced and no movement or encounter handler was replaced.

## Correction and preserved coverage

Pin `encounter_rng.seed=0` once per floor after the legal ticket/portal/collision route and remote map-position settlement. Do not reseed each step, force a hit, select a troop, change pressure, or inject battle state. The real source step/weighted group/enemy selection still consumes the RNG. This input reaches its first hit on step 19; the test retains its original 160-step maximum rather than asserting a particular draw count.

The observation subclass also verifies each actual navigation arrival sends and completes exactly one field step, with one accepted position report at the intended map/cell. Each request must permit encounters, be accepted at the authoritative position, and advance the RNG. The existing socket round-trip after arrival remains the completion barrier. It needs no new sleep or deadline: `handle_arrival` sends position and field step synchronously, before the next frame can observe the completed move; the following ping drains this connection's preceding commands.

Original assertions remain: legal route authority, source collision, natural battle opening, remote battle scene/transition/enemy entrance, original per-band enemy IDs, settlement and released movement input. Headless validation proves these scene states, not rendered pixels.

## Evidence

External complete logs are retained:

- `/private/tmp/full195-golden-probe.log`: unseeded instrumented run, zero failures.
- `/private/tmp/full195-golden-rng.log`: original RNG input search; seed 0 hits at 19, seed 6 misses all 160.
- `/private/tmp/full195-golden-seed6-reproduction.log`: real GameScene/WS failure reproduction at 820.
- `/private/tmp/full195-golden-seed6-summary.json`: 160 accepted requests, 160 RNG advances, zero hits. Its 181 position reports include 21 route/setup reports as well as 160 walking reports; none were rejected.
- `/private/tmp/full195-golden-fixed.log`: final targeted suite with request/RNG observations and completion result.
- `/private/tmp/full195-golden-fixed-parse.log`: retained intermediate missing type-annotation diagnostics, corrected before final validation.

The slot retains the enabled private catalog SHA `c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92` and world manifest SHA `5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639`. No import, main/live write, full suite or unrelated test was performed for this correction.

Final result: `GOLDEN BUI WALKING: 0 failures`, process exit 0. Each of 800/820/840 recorded 19 accepted real steps and one hit, selecting original groups 708/709/710 respectively. The reproduction exited 1 at the unchanged 820 natural-battle assertion as intended; that diagnostic failure is preserved, not reported as a passing suite.
