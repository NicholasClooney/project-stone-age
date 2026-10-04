# Fixed equal-world A/C mode compatibility — passed

Only quest_auto_public_corridors_same_world_test ran once, A/C only, require_escalated in its own isolated Stone Age tests folder. No B/encounter/other suite/import. Original uncontrolled evidence and strict failures are preserved separately. Window released immediately on completion.

- UTC2026-10-04T17:29:42.658783–17:30:01.323427.
- External wall **18.665s**, internal **17.615s**; exit0.
- **1312 assertions, 0 failures**; process56638 exited, no timeout.

## Fixture and actual equivalence

Seed1 was fixed a priori in the previously reviewed draft, not searched or changed following any run. Both Backend instances passed the assertion that original npc_state.version=0 and records/spawn_attempts are empty BEFORE setting only spawn_rng.seed. Normal source birth was then allowed to occur via existing refresh flow. No records cleared, coordinates injected, clock/enable set changed, field/battle RNG seeded, or arrival/event state forged. Real job12 REQUEST and original village portal executed.

Mode compatibility uses the disclosed strong character and no_random_encounters=true. This is not a natural encounter run; encounter proof remains separate/unrun.

Both modes had11 paired actual in-plan local_path calls. All complete normalized occupied arrays and hashes, NPC versions/projections, enabled-event arrays, map/origin/goal inputs matched. Comparison reports equal=true and differences=[]. Both had2 actual plan calls; no turn replan.

Original area-born NPC in both: `seimu/event/event02_1@100:230:180:area:525:200` at100(239,189); version2. Other TimeMan projections all changed and identical.

Public search input (origin259,171 / goal622,190):
`[[239,189,true],[278,325,true],[346,356,true],[443,127,true]]`
SHA256 `abdd44c7707408be943c61a1f830088944a6938f0c6a93e00fb5f65494f97c1d` in both A/C.

## Actual route and timing

| | A | C |
|---|---:|---:|
|Complete moved positions incl original portal|383|383|
|Original field_step logical calls incl door|382|382|
|Simulated public travel seconds|76.200|38.100|
|Mode internal wall|8.232s|9.098s|
|Fast committed-prefix position packets|0|381|
|Maximum committed prefix|0|3|

Whole moved-position arrays and whole field_step arrays are equal; first-difference objects both empty. This asserts complete fixed path equality, not just endpoint/count/length. C cadence is2x by simulation; wall is separately reported and is not acceleration evidence.381 denotes packets, not segments.

Both actually approach the reviewed new public-v2-yam-mati corridor and independently walk original door100(622,190) then original portal1300(24,59). Normal save/load readback of real request state/items/location/battle history passed. This stops after the approach; no claim of completed job12 delivery or ninejob acceleration.

## Exact conclusion and remaining work

**Fixed equal-world mode compatibility passed on this representative new corridor.** Do not rewrite it as reproduction of the old index362 failure's complete cause. Earlier uncontrolled A input was unrecorded, and the later uncontrolled-input run had different worlds but identical paths. All those facts remain.

No production/navigation/core change was needed during the diagnosis. B boundary evidence remains the previous actual run; it was not repeated here. Encounter child suite, chain12/13/5/9, public24/independent25/continuous25 and legacy-three incremental benefits still await their own windows. No new hash or ninejob delivery claim.

Evidence in /private/tmp/tmux-agents/quest-auto-v2-navigation:
- public-expansion-same-world-first.log
- public-expansion-same-world-first-meta.json
- public-expansion-controlled-birth-inputs.json (full copied trace; original isolated user:// retained)
