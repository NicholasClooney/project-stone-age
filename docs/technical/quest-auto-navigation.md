# Automatic quest routes

Mode A uses `quest_auto_navigation.gd` only as a geometry planner. The runner owns movement, original passage checks, per-cell encounters, map acknowledgements and transactions. A cached route is revalidated against the current authoritative cell and dynamic NPC state; invalid geometry is planned again once. Planning never creates arrival proof.

`quest_auto_navigation_test.gd` executes the full original task and checks every adjacent cell and exact portal for:

- Adult rite (job 1): Samgir manifest spawn → 100 → 1100 → 10201 → 10202 → the original level-30 portal → 10204, both channel walks and all three exchanges.
- Shell delivery (job 11): Samgir manifest spawn → original village request → 100 → Marinas and the original exchange.
- Herb delivery (job 30): Tamutamu manifest spawn → 3110 → 200 → all five Haro floors → the original return route and final exchange.

The suite disables ordinary encounters using the existing profile setting to isolate route geometry. It does not replace the separate real-combat, save/resume and WebSocket tests. No test imports art or uses the live save.

These routes do not prove travel from every possible starting island. In particular, the two permit guards at 10202 are distinct from the level-30 adult entrance. Their original scripts `genout/wpm_10202_22_28` and `genout/wpm_10202_22_32` require the existing travel permit and warp across disconnected same-map chambers. Until the separately audited server transaction and planner integration land, that route stops for manual handling; it never buys a permit or substitutes a project jump. Protected cave restarts still require new legitimate arrival.

B/C remain unavailable until their geometry, authority executor and client acknowledgements are separately integrated and tested. Neither a public map ID nor a successful geometry path authorizes project movement.
