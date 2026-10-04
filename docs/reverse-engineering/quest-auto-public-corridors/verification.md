# Execution verification handoff

Production original commit: d758291738eab876420f8a3dd42475da120e2bf9, based on b5ec513c. This follow-up adds tests and evidence only. No backend, arrival, navigation/A planner, source service, UI or shared suite registration changes. Integration/full/main publication remain the coordinator's responsibility.

## Unique formal suites: 12

Every name below has prefix `quest_auto_public_corridors_` and suffix `.gd`, in `client/tests`. All passed serially in their assigned single-process windows. Times are measured process wall costs, not in-game acceleration. Listed deadlines are the per-test condition budgets / authorized outer limits, not changes to the shared runner budget.

|Name|Assertions|Wall seconds|Coverage|
|---|---:|---:|---|
|geometry_test|113|2.529|37 source candidates,29 accepted,8 rejected|
|interfaces_test|555|25.807|Production audit/validate/next_segment, dynamic blockers,24 stride/5 walk|
|same_world_test|1312|18.665|Fixed equal NPC world, complete A/C inputs and movement/field sequences|
|encounter_test|23|6.545|Original second-cell hit, prefix truncation, compact victory/save/replan, stale ACK/cancel|
|b_boundary_test|28|7.160|New B outside landing/no proof/full ACK hold/separate original door/portal/save readback|
|letters_test|8732|28.939|Real B/C12→13, original grants/consumption/END/readback|
|goya_test|15509|43.394|Real B/C24→continuous25, continuous25 new/old fast0|
|marju_b_test|28178|42.404|Real B5→9, FREEWARP/maze/exit/random reward/readback|
|marju_c_test|46272|58.666|Same real C5→9 with adjacent bounded prefixes|
|legacy_approach_test|13320|54.254|Six B/C1/11/30 incremental approaches, original target/door/protected step or REQUEST|
|public25_b_test|14284|33.783|Earn24 END7, player original reverse exit/Jaja walk, new independent25|
|public25_c_test|42307|43.291|Same C scenario plus full field/commit equality and adjacent prefix<=3|

Public25 condition170/outer180; Marju170/180; legacy140/150; letters110/120; Goya140/150; B boundary50/60. No new300-second runner exception is needed from these measured runs. Tests were not repeated simply to collect timing, and no sustained concurrent timing is claimed.

## Explicitly do NOT register

`quest_auto_public_corridors_execution_test.gd` is the original uncontrolled ABC diagnostic and inherited support; its two strict A/C comparisons failed. `quest_auto_public_corridors_world_inputs_test.gd` is uncontrolled passive-input diagnostic/support. Neither is a formal green suite. Formal same_world and B-only entries reuse their support without running those diagnostic `run()` bodies. `support/quest_auto_public25_support.gd` is support only.

Original diagnostics and failure reports are retained under `evidence/`, including startup before suite, stale-occupancy fixture failure, uncontrolled A/C first difference362 and legacy raw float/int coordinate mismatch. Full original logs/JSON remain in `/private/tmp/tmux-agents/quest-auto-v2-navigation/`; do not replace them with later successes. The controlled same_world fixture seeds NPC birth only, before any refresh with no existing birth state; it neither controls field/battle RNG nor reconstructs the old failure's full cause.

## Actual task benefit and limits

29 new lanes +7 unchanged =36 production candidates. Only7 new unique IDs have real execution hits: public-v2-yam-mati, mati-yam, jaja-goya, mati-marju, marju-mati, marinas-kou, yam-samgir (each carries public-v2-). Repeating one lane in several jobs does not increase this count. The24 stride/5 walk interface result is not an actual task benefit count.

Jobs12/13/24/5/9 have B/C new-lane hits in real completion chains. Jobs1/11/30 cover incremental public approaches and the original first protected step/REQUEST only, not new complete legacy-chain runs. Continuous25 is entirely protected with new/old fast0. Independent25 starts only after real24 END7, actual reverse original doors and a deliberately chosen player walk back to Jaja:367 protected+530 public adjacent cells and6 original portals. That excursion is not the planner's route and is never credited as continuous25 speedup. Both independent modes have actual jaja-goya hits and original25 completion/readback.

A/C compatibility uses actual full original field/position arrays in an equal NPC world. C prefixes are at most3 adjacent logical cells; an independent original-encounter test proves the first hit truncates the remaining segment, ordinary attack+compact victory/save/replan, and old ACK/cancel cannot resurrect it. Explicit strong-character/encounter-off compatibility fixtures are disclosed separately from that encounter proof. B project landings do not create scope/marks/stages/approach proof and do not swallow original doors.

The8 map300 rejected candidates remain unresolved original-A geometry failures, never bypassed with B. Script-NPC public approaches remain A;300 approach pockets and10202 gates/caves/mazes remain protected. No claim that all29 lanes have real execution coverage. Detailed per-job simulated time, field/protected counts, rewards and source doors are in the preserved handoffs. Wall is separate; minor protected simulated-time differences are not speedups.
