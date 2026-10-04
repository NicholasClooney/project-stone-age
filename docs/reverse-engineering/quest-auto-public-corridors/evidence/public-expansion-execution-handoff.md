# Actual execution first result — two sequence failures

## Run identity and environment

- pool-b / feat/quest-auto-public-corridors / base b5ec513c; uncommitted, no delivery hash.
- Only quest_auto_public_corridors_execution_test, once after the explicitly authorized startup-environment correction. No encounter/other suite/import/full.
- Earlier 1.045s logger crash is preserved separately in execution-first files; it did not enter the suite.
- Read-only environment evidence: STONE_AGE_TEST_USER_DIR initially unset; run.sh computed `Godot/app_userdata/Stone Age tests/pool-b-2707629622`. Real directory/log permissions 0755/0644, uid501, resolved paths remain under `~/Library/Application Support/Godot/app_userdata/Stone Age tests/`, not real game user://. That Library root is outside workspace-write permissions.
- Authorized run used require_escalated and explicit isolated `Godot/app_userdata/Stone Age tests/pool-b-public-corridors-execution-20261004T1715`. Original headless/muted run.sh command, fixture and 60s outer limit unchanged. Engine started normally and suite parsed/executed; supports startup sandbox/log access attribution for earlier crash.
- UTC 2026-10-04T17:14:02.467543 → 17:14:26.629731.
- External wall **24.162s**, exit **1**; suite internal **23.142s**.
- **1334 assertions, 2 failures**. Process96581 exited normally with test failure code, no timeout. Window immediately released by notice.

## Measured evidence

| Mode | Original field_step calls on field leg including door | Fast position packets | Simulated public travel seconds | Mode internal wall |
|---|---:|---:|---:|---:|
| A | 382 | 0 | 76.200 | 8.157s |
| C | 382 | 381 | 38.100 | 8.980s |
| B | 2 | 1 | 0.200 | 5.925s |

C381 counts per-cell committed-prefix position packets, NOT 381 distinct segments. Cannot use it as segment count. Both A and C field calls include the door step; C prefixes were bounded<=3. Simulated ratio A/C=2, but this does not override the failed full-sequence checks.

Passed assertions: real job12 REQUEST/letter and original village exit for all modes; current target proposes the exact public-v2-yam-mati audit; actual fast executor retains that identity; all modes reached100(621,190), separately walked100(622,190), then originalportal1300(24,59). B creates no scope/marks/stages/approach proof, stays outside without ACK, full identity ACK permits separate door step. Normal save/load preserves actual event/items/location/battle history. These are representative approach results, not completed job12 delivery or ninejob benefits.

The two failures:
1. Complete actual A/C moved-position sequence including original portal is not equal.
2. Complete original field_step logical sequence A/C is not equal.

No assertion relaxed, no production/A change, no automatic rerun. The first-run log prints aggregate counts but not the arrays/first differing index, so root cause cannot yet be located to a cell or classified as production route divergence versus observation/fixture history. Do not infer equal paths from equal counts/endpoint/time.

## Static investigation / next minimal evidence

Navigation.plan selects actual shortest original door path; public_routes.audit requires the proposed route to equal the reviewed full suffix. C corridor calculation calls Navigation.local_path on the same planner's AStarGrid2D cache while A does not call that audit; equal-cost path/search history is a hypothesis to investigate, NOT a diagnosed bug. Other possibilities include retained route changes over task startup or test observation. No proof currently selects among them.

Next narrow diagnostic should preserve full per-mode position and field_step arrays in isolated user:// and print the first differing index+neighbours, along with selected full A plan at public entry and actual C proposals. Do not prewarm/change A or force a door to match C. It can remain the same suite/coverage under a separately granted one-run window. No production edit is justified until actual divergent cells and origin of divergence are shown.

Original source table29+old7, five interfacewalk, eight300 exclusions and script gaps unchanged. Encounter child suite still unrun and must remain a separate window. No fast>0 ninejob completion claim.

Logs: `public-expansion-execution-authorized.log` and `public-expansion-execution-authorized-meta.json` in this report directory. Earlier launch evidence remains `public-expansion-execution-first.log` / `-first-meta.json`.
