# Golden antelope legitimate helper navigation

This slice consumes the independently reviewed golden arrival policy
(`b4df5cf`; local integration equivalent `d7caecb`). It does not change backend,
automation, arrival policy, ordinary eye drops, source conditions, or rewards.

`GoldenArrival` is separate from `GoldenBui`. Its helper hooks cover only
29/30/54; map31901–31911 NPCs and the existing encounter instruction cannot
supply a cave shortcut. Outside guidance leads adjacent to the actual
300→31901 entrance with an empty target NPC ID. Inside, navigation is only a
no-op at the current interaction position, after checking the current original
branch and server arrival/action proof. Completed steps are not made current.
Public source NPCs, including Kuy's mirror and return exchanges, retain their
original eligibility and public navigation. An actionable public exchange takes
priority over the cave entrance guide.

The actual source sequence remains the original entrance, three floors, key
gate `genout/wpm_31903_39_4`, middle floors and `giiru/event/event30_7` guide,
then consuming truth door `genout/wpm_31910_8_9` to31911(6,15). The guide requires
`ENDEV=4&NOWEV=29&ENDEV=30&NOWEV=54&ITEM=2548`; a fixture with only NOW29 and the
eye must be refused. Only the saved truth-door transaction grants the authority
for `event30_6` to award2551, END29 and Charm1. Wrong doors keep their original
consumption and return coordinates, without truth proof.

## Targeted verification boundaries

The source-route tests send actual report_position steps and actual original
dialogue/gate commands. Starting public departure coordinates are fixture setup,
not an authority grant. No test assigns an arrival scope, epoch, mark or permit.
The wrong-door and isolated two-socket tests explicitly supply earlier source
flags/key/eye. They do not claim those fixtures naturally acquired the eye.
The retained ordinary messenger tests use controlled source group/RNG battle
configurations to check existing loot; they do not claim natural field spawning.

`golden_helper_arrival_test` covers all original cave NPCs' outside boundary,
public Kuy priority, fabricated final-room placement, actual entrance/key/guide,
two real sockets, stale/consumed tokens, failed truth save and successful retry,
real persisted Warp/consumption, final armor/Charm1/END29 atomic save failure and
retry/readback, and restart refusal. `quest_arrival_golden_test` remains the
independent route oracle. Remote legacy UI tests retain real source clicks.

## Preserve coverage without one long mixed suite

The five brothers fixture now completes the real papers/crystal/REQUEST31 once,
walks all five guards and four actual decoy exits, and reaches the hall through
the real fifth corridor. Each guard retains its own rollback/retry assertions.
The five mutually exclusive pet cases restore only the source-earned pre-reward
profile snapshot at that legitimately reached hall, walking to each source NPC;
they do not copy or assign arrival state. This is alternative transaction
fixture coverage, not a claim that gameplay repeatedly grants five pets.

The former mixed test is split, retaining all assertions:

- `brothers_golden_quests_test`: five guards, four decoys, five pets, first mirror
  golden route after brothers, original crystal reload and two-device request.
- `golden_replacement_route_test`: exact wrong-door consumption/return, real
  replacement-mirror route (no antelope), then brothers original request.
- `brothers_party_retry_test`: all three failed-save slots and every original
  personal slice, UID, HP/XP/currency, persistence and nonduplicate assertion.

Each prints monotonic stage timings. An external perf_counter wrapper records
process elapsed time for the final sequential targeted run. No global timeout
is changed; runner ownership remains with the coordinating agent.

Final local sequential process timings (perf_counter, targeted, no full run):
225.92s / 68.29s / 29.23s for the three suites above; all exit0 with no script,
engine or assertion errors. Stage details are retained in
`/private/tmp/foundation-golden-split-timing.json`. These are observed local
measurements, not a guarantee under arbitrary concurrent machine load. The
prior 338.50s mixed attempt failed its incomplete wrong-door fixture and is
not counted as passing validation or used to justify a timeout exception.
