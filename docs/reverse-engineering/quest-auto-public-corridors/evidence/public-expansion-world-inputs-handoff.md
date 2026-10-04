# Uncontrolled A/C actual input diagnostic

Only quest_auto_public_corridors_world_inputs_test ran once under require_escalated, isolated test directory. No B/encounter/same_world/other suite/import. Window released immediately on exit.

UTC2026-10-04T17:25:33.735668–17:25:53.037374; external wall **19.302s**, internal18.213s, exit0; **1309 assertions / 0 failures**. This is an uncontrolled-world diagnostic pass, NOT equal-world proof and not a dismissal of the original failures.

| | A | C |
|---|---|---|
|Actual plan calls|2|2|
|In-plan local_path calls|11|11|
|Field_step calls on leg|382|382|
|Full moved positions incl portal|383|383|
|Simulated public seconds|76.200|38.100|
|Internal mode wall|8.554s|9.370s|
|First position/field-step difference|none|none|

Both strict full arrays were equal this time. No assertion weakened. Actual request/village exit, door and portal, normal save/readback retained.

## Input difference (actually recorded, not inferred)

Original area-born NPC `seimu/event/event02_1@100:230:180:area:525:200`:
- A: map100(384,198)
- C: map100(327,192)

Both npc_state.version=2. Full enabled-event arrays match in all paired actual calls, and all map/origin/goal triples match. TimeMan records all remain `time_mode=changed` and match. The one NPC location is the only full snapshot difference. All11 call snapshots differ because they include this world state, including3 village searches where local occupied arrays themselves are equal.

First public search (paired local_calls[3]): map100, origin259,171, goal622,190.

A normalized occupied:
`[[278,325,true],[346,356,true],[384,198,true],[443,127,true]]`
SHA256 `02ae0a02d192900b6e7272e43d64c1ecd3a21846a2b5c2b06b989eb6112ff023`.

C normalized occupied:
`[[278,325,true],[327,192,true],[346,356,true],[443,127,true]]`
SHA256 `d7e1880ebd6e8d70123b07dd2e383b57dfbe597e4c33dd9e6879cb2cca95ba61`.

These occupied inputs differ throughout all8 public candidate-door searches. Three prior village searches have identical occupied `[[69,89,true],[71,76,true]]`, SHA256 `cbf08df228d2c878f2a69ba9bca0a2056aa4e4a52009d1aa0486c744c094867c`. First public grid_key_before matches (`140020372821323726597655`) while block_key_before differs by actual NPC override hash. No extra refresh/search was added.

## Conclusion and outstanding proof

Independent uncontrolled backend fixtures do not represent the same complete planning world. That is now established by actual occupied inputs, not just C/B hash inference. This run's two different worlds happened to choose the same path. It cannot retroactively reconstruct the previous run's unrecorded A occupied set, so do not claim a conclusive causal reproduction of the earlier one-cell mismatch.

Original two failing logs/full traces and first index362 remain intact. No evidence of core segment changing its selected A plan, and no production edit made. Equal-world sequence contract remains to be verified through separately authorized same_world draft; no seed searching or clearing state. Seed1 draft remains untouched/unrun.

## Evidence

- public-expansion-world-inputs-first.log
- public-expansion-world-inputs-first-meta.json
- public-expansion-uncontrolled-inputs.json (full trace copied here, original still in isolated user://public-corridors-uncontrolled-inputs.json)

All are under /private/tmp/tmux-agents/quest-auto-v2-navigation. New source table/29+7/300 exclusions and ninejob benefit scope unchanged.
