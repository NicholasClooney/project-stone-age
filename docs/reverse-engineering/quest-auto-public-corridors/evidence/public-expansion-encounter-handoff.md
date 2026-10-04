# New corridor original-encounter acceptance — passed

Only `quest_auto_public_corridors_encounter_test` ran once in the explicitly allocated window, require_escalated, headless/muted, isolated Stone Age tests folder. No other suite, import or full run. No product/core/enemy/outcome edits. Window immediately released on completion.

- UTC2026-10-04T17:36:40.794766–17:36:47.339849.
- External wall **6.545s**; suite internal **5.567s**.
- **23 assertions, 0 failures**, exit0; process20876 exited before60s outer budget.
- Independent original encounter oracle selected **seed7** as a deterministic second-cell-first-hit fixture.

## Actual tested lifecycle

1. Real job12 REQUEST grants letter, original village exit reaches100(259,171). Actual task proposes a three-cell `public-v2-yam-mati` stride. No quest/proof/receipt fabrication.
2. Original EncounterCatalog.step with current pressure finds a seed whose first hit is the second logical cell. Only field encounter RNG is seeded for this explicitly deterministic test; enemy table and battle outcome/RNG are unchanged.
3. Actual ObservedBackend._cmd_field_step forwards to the original method. Exact recorded call array equals only proposal points0 and1; authority stops at point1. Point2 never executes or rolls encounters before battle.
4. Existing ordinary attack/compact lifecycle is actually open and owned by quest automation. A stale committed-prefix ACK and large tick cannot execute the discarded tail.
5. Existing automation drives actual victory. Battle closes, completed_battles is nonempty, normal quest battle save succeeds, and a new movement segment is issued from actual hit position. No forced victory or manual profile reward mutation.
6. Explicit stop then stale ACK and another large tick cannot change position or add a field_step. Normal save_game/load_game preserves earned request/items/location and actual completed battle history.

Preparation suppresses random encounters so request/village exit reaches the targeted new segment. The first-hit phase ENABLES the original encounter logic. After exact truncation assertions, subsequent random encounters are suppressed solely to bound the saved-victory continuation check. Strong level140/stat fixture is inherited and disclosed. This deterministic lifecycle test is not a natural encounter distribution, balanced combat or ninejob route benchmark.

## Evidence and scope

- public-expansion-encounter-first.log
- public-expansion-encounter-first-meta.json
- client/tests/quest_auto_public_corridors_encounter_test.gd

The log reports all assertions passed and seed7; assertion code compares actual cells to the three-point original proposal. No extra diagnostic rerun was needed. Fixed equal-world A/C and previous B boundary evidence remain separate. Old uncontrolled sequence failures retained, not overwritten. Ninejob actual chains/benefits still pending their own windows; this result is only the representative new corridor's encounter/continuation boundary.
