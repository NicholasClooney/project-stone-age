# Area spawn regression after TimeMan activation

The full-suite failures were two stale assertions on the entire per-character
`QuestNpcState.records` dictionary, not failed collision sampling or a second
random draw. The actual failure was reproduced on the fresh pooled checkout with
the production registry and imported catalog. Diagnostics are in
`/private/tmp/foundation-area-root-cause.log`.

At both the restart check and the second-character check the dictionary contained
exactly the four `genout/tman_400_*` identities, each with `time_mode: changed`.
The Katan identity had no record. Its spawn attempt was at injected time1101.0.
`refresh_npc_state` now legitimately updates TimeMan projections as well as area
births; `records.is_empty()` therefore does not describe a failed Katan draw.
The earlier fixture-install fix remains needed to replace production event35's
same ID and clear only that ID's old birth/attempt/projection. It was correct but
did not fix these two later whole-dictionary assertions.

The test now verifies the exact intended behavior independently:

- The Katan record and active NPC are absent after the blocked first draw, and
  the second character's public projection has no birthplace.
- Its attempt timestamp matches the injected personal spawn clock.
- The spawn RNG state equals exactly one draw from the original blocked seed.
  No seed was replaced, no draw skipped, and no retry interval relaxed.
- Every active TimeMan retains its independent mode record. The shared world
  clock is held at one known phase within this test and restored afterwards;
  the personal spawn clock still advances across 0.999/1.0 second boundaries.

There is no runtime change, global state clearing, or change to source collision
rules. Existing successful birth stability, actual terrain checks, save/restart,
same-character devices, independent characters and later retry remain covered.
