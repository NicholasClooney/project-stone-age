# Automatic quest routes

Mode A uses `quest_auto_navigation.gd` only as a geometry planner. The runner owns movement, original passage checks, per-cell encounters, map acknowledgements and transactions. A cached route is revalidated against the current authoritative cell and dynamic NPC state; invalid geometry is planned again once. Planning never creates arrival proof.

`quest_auto_navigation_test.gd` executes the full original task and checks every adjacent cell and exact portal for:

- Adult rite (job 1): Samgir manifest spawn → 100 → 1100 → 10201 → 10202 → the original level-30 portal → 10204, both channel walks and all three exchanges.
- Shell delivery (job 11): Samgir manifest spawn → original village request → 100 → Marinas and the original exchange.
- Herb delivery (job 30): Tamutamu manifest spawn → 3110 → 200 → all five Haro floors → the original return route and final exchange.

The suite disables ordinary encounters using the existing profile setting to isolate route geometry. It does not replace the separate real-combat, save/resume and WebSocket tests. No test imports art or uses the live save.

These routes do not prove travel from every possible starting island. In particular, the two permit guards at 10202 are distinct from the level-30 adult entrance. Their original scripts `genout/wpm_10202_22_28` and `genout/wpm_10202_22_32` require the existing travel permit and warp across disconnected same-map chambers. The separately audited server transaction saves the fixed destination before a script move and requires a new same-map acknowledgement. Navigation proposes only the exact source identity from the reachable guard side. With an existing permit, the new cross-island route test completes both original gate directions; without one it remains manual. It never buys a permit or substitutes a project jump. Protected cave restarts still require new legitimate arrival.

B/C remain unavailable until their geometry, authority executor and client acknowledgements are separately integrated and tested. Neither a public map ID nor a successful geometry path authorizes project movement.

## Audited public segment proposals

`quest_auto_public_routes.gd` holds exact source landing / next portal tuples, including the imported portal source identity. For each tuple it computes the ordinary A path. A B/C proposal is allowed only when the current A route is that canonical path's complete remaining suffix. A public map number alone grants nothing.

B's only project destination is the final ordinary cell immediately outside the next original portal. The portal itself, map change and any original gate transaction remain separate normal steps. C uses at most `C_MAX_CELLS` consecutive cells of the same A suffix. Its speed, individual encounter rolls and first-encounter truncation belong to the core executor, not the planner.

The initial reviewed corridors are:

| Original source landing | Next original portal | Imported source |
| --- | --- | --- |
| 100 (637,494) | 100 (78,614) → 2000 (72,33) | `100warp.create:169` |
| 100 (79,614) | 100 (638,494) → 1000 (50,119) | `100warp.create:34` |
| 100 (706,488) | 100 (474,631) → 1100 (67,35) | `100warp.create:349` |
| 1100 (67,35) | 1100 (96,62) → 10201 (6,4) | `dungeon00.create:214` |
| 3100 (84,77) | 3100 (44,55) → 3110 (15,21) | `warp_y2.create:907` |
| 200 (426,94) | 200 (452,162) → 20101 (29,69) | `dungeon01.create:349` |
| 200 (452,162) | 200 (427,94) → 3100 (33,79) | `200warp.create:439` |

The return landing at 200 (452,162) overlaps a portal and first leaves it with an ordinary walk. No corridor contains a portal, a current NPC, a protected cave or the map-300 approach pocket. In fact, none of map 300 is accelerated by this initial review. Unreviewed public routes use A; missing A routes remain manual.

`next_segment` returns local `from_map`, `from_cell` and `navigation_key` metadata in addition to the frozen kind/points/audit_id fields. The core preserves the proposal and adds `remaining` as an exact suffix after each committed cell. `validate_segment` checks the current authoritative cell against the executed prefix and rechecks the corridor, NPC state, level and permit; B additionally replans the current A route. These local fields are not client movement authority. Core-generated run/step/revision/segment/sequence identity and acknowledgement handling are separate.
