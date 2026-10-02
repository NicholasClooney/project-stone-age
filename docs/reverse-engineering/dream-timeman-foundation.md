# Four original dream TimeMan projections

## Explicit manifest handler

Declare the four scripts under `handlers` as `{ "kind": "timeman", "events": [34] }`:

- `genout/tman_400_95_120`
- `genout/tman_400_98_120`
- `genout/tman_400_85_102`
- `genout/tman_400_88_102`

Pin the source scripts, both actual `genout/mugendungeon.create` and
`genout/mugendungeon2.create`, `genout/npcgen.template`, `gmsv/npc/npc_timeman.c`,
`gmsv/handletime.c`, and `gmsv/include/handletime.h` in `sources` as usual.
The actual create/template must bind `TimeMan`, with the reviewed original map,
cell, direction and graphics. Other scripts, phases, CLS and randomized dialogue
are deliberately unsupported. `client/tests/fixtures/dream-timeman.json` is a
complete minimal executable manifest and its source-derived module.

## Original behavior and project projection

`npc_timeman.c:50` defines AFTER as born 126/dead 300. Init at 59–94 stores original
and changed graphic IDs; Watch at 173–195 uses strict `126 < hour < 300` for mode
0 and the original graphic, otherwise mode 1 and the changed graphic. Talk at
130–146 chooses the corresponding original string. The four reviewed scripts
contain no comma-separated alternatives, so there is no dialogue RNG to emulate.

The project projects the current mode before lookup and on the server tick using
the same `OriginalWorldClock` as the entrance gates. This supplies the state an
original nearby-player Watch would select; it does not expose the original brief
initialization state before the first Watch. All characters/devices share this
clock, while projection records use the existing ephemeral per-character state.
No player save field changes. No flag transaction occurs when opening/closing
this read-only dialogue. Source time of day and AFTER differ: at hour 300 the
A portal is open, while these TimeMan already show their changed graphics/text.

Only `time_mode` is broadcast in public NPC overrides. The catalog maps that mode
to the original image and text; the NPC stays at its original map/cell. The
existing resident refresh rebuilds its sprite and preserves collision at that
same cell. No hidden flag or movement is introduced.

| Source cell | Original graphic | Changed graphic |
| --- | --- | --- |
| 400 (95,120) | 16203 | 16200 |
| 400 (98,120) | 16202 | 16200 |
| 400 (85,102) | 16202 | 16204 |
| 400 (88,102) | 16201 | 16204 |

Both modes are exported with their original bitmap offsets to collision-safe
quest image paths. Web pack planning assigns both to map-400; switching mode
never depends on fetching an unrelated NPC's pack.

## Verification boundary

Source tests verify all four real bindings, reject unreviewed source/template
changes, compare both exported PNG modes byte-for-byte to the original archive,
and run the real web pack planner on an isolated map/catalog fixture. Runtime
checks all original graphic/text pairs at 126/127/299/300/700/701, unchanged
map/cell/profile, no version churn within a phase, and two real sockets receiving
identical mode updates, including a lookup occurring before the publishing tick.
Remote dialogue ignores a client-supplied fake mode. Headless tests do not certify
rendered pixels; complete dream route/rendered acceptance remains with its route
owner. This does not activate the quest or decide its repeat-reward policy.
