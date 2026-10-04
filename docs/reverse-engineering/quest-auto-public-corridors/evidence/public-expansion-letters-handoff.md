# Actual B/C job12 -> job13 chains — passed

Only quest_auto_public_corridors_letters_test ran once under require_escalated in an isolated Stone Age tests directory. No other suite/import/full. Window released immediately on exit.

UTC2026-10-04T17:42:21.999019–17:42:50.937486; external wall **28.939s**, internal27.936s; exit0; **8732 assertions, 0 failures**. Process73238 exited without timeout. Original outer120s/condition110s budgets unchanged; no extension required. This first actual measurement does not justify any >300s timeout entry.

## Actual per-job evidence

| Mode/job | New lane | Fast packets / distinct segments | Field_step calls | Moves | Protected walk | Unaudited walk | Door walk / original portals | Sim total seconds | Map100 sim seconds | Job wall |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
|B12|public-v2-yam-mati|1 / 1|52|54|0|49|2 / 2|12.2|0.6|4.976s|
|B13|public-v2-mati-yam|1 / 1|49|51|0|46|2 / 2|11.6|0.6|4.184s|
|C12|public-v2-yam-mati|381 / 127|432|434|0|49|2 / 2|49.8|38.5|8.054s|
|C13|public-v2-mati-yam|380 / 127|428|430|0|46|2 / 2|49.1|38.4|7.388s|

All four completed=true and saw_actual_letter=true. Old-audit hits are **zero in all four**. Each new lane audit identity was read from the actually executing proposal, not inferred from map ID. Prefix packets are not counted as independent segments. Field_step calls include all same-map logical commits (a B jump calls the original encounter entry at its one committed landing), and equal total moves minus original portals.

Map100 simulation includes actual movement cadence on that map, including original door/portal steps. It is separate from total simulated task time and actual test wall. This suite did NOT rerun full A chains; do not claim a measured full-chain A-to-C wall speedup. Earlier fixed equal-world representative A/C 2x simulation remains a separate assertion.

Letters have no protected internal route: protected_walk=0 is correct, not omitted protection. Unaudited village walking, original door steps and original portals remain separate actual categories.

## Original transactions and save/readback

Each mode starts its own new profile/backend at1400(68,90), no original task events/items/proof injected. Job13 starts continuously at job12's actual completion position.

- Job12: observed actual REQUEST letter2416 and NOW3; original delivery consumes2416 and setsEND3, with no premature2448.
- Job13: observed actual REQUEST letter2423 and NOW5; original return consumes2423, grants exactly one2448 and setsEND5 while preservingEND3.
- After EACH actual completion, normal save_game/load_game preserves full original events/items and saved actual location. No forced endpoint.
- Full run/step/revision/segment/seq/map/cell/connection ACKs; map changes match actual original source portal+target. Ordinary movement adjacent; fast destinations outside doors/protection/approach, C committed prefix<=3.

## Fixture and benefit boundary

Explicit mode compatibility: strong level140/original route stat fixture, no_random_encounters=true. Only normal NPC birth seed1 fixed before any refresh, with empty version/records/attempts checks; no field/battle seed, victory manipulation or selected-route seed search. Natural encounter proof is the separate passed encounter suite.

**Actual new-lane benefit is now established for job12 and job13 in both B and C** (not just geometry/interface tables). Does not establish jobs5/9, public24, separate public25, continuous25, old1/11/30 or future routes. No change to the requirement that continuous25 fast=0; no change to five interfacewalk results or eight excluded300 corridors/script gaps. Production/core not changed for this test.

## Evidence

In /private/tmp/tmux-agents/quest-auto-v2-navigation:
- public-expansion-letters-first.log
- public-expansion-letters-first-meta.json
- public-expansion-letters-results.json (copied full per-job artifact; original isolated user:// retained)

Suite source: client/tests/quest_auto_public_corridors_letters_test.gd. Original branch/main dependency remains b5ec513c. No new commit/hash claimed here; shared suite registration and integrate/full belong to parent integration.
