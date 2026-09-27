# Whole-map navigation and developer teleport

Use **DEV → 地图导航** to open the map navigator. The dropdown browses every imported map without moving the player. The view covers the complete current island, including800×1200 Jaruga. Yellow markers are NPCs, cyan markers are original doors/exits, and white marks the player when viewing their map.

- **步行** is the default. Click a map point or listed point of interest to walk there. Cross-map navigation follows original portal links and physically walks each segment. The map closes when walking begins.
- **DEV 传送** explicitly bypasses walking and gates. Click to land on nearby walkable ground, excluding NPC cells and automatic portal triggers.
- Scroll to zoom toward the pointer; drag to pan; **居中 / 全图** restores the full extent. Esc closes the navigator.

Walking across islands requires the original reusable undersea permit. At the original guard, navigation opens the existing confirmation dialogue and waits for the player to confirm. It does not silently jump across the checkpoint. Cancelling that dialogue stops the route. Manual movement, another movement target or battle interrupts the route; focus loss does not. After combat, choose a destination again.

The view uses original automap ground colors with gridXright/Ydown orientation. Its cached texture retains one texel per grid cell on both islands and is bounded at1600×1600 for larger future maps; zooming and panning do not recreate thousands of terrain sprites. Only one browsed map's JSON and texture are retained. Clicking unwalkable terrain resolves to a nearby reachable cell for Walk; Teleport searches within32cells and reports failure when no safe ground is available.

## Verification

All runs are muted:

- `travel_router_rules_test.gd`: original graph connectivity, permit enforcement, avoiding unintended doors and restoring navigation collision state.
- `travel_router_test.gd`: remote browsing, pointer-centered zoom, actual shop-door traversal, focus persistence and manual cancellation.
- `dev_map_overview_test.gd`: explicit teleport, real pointer input, map-coordinate conversion and full-island bounds.

Walk routing currently chooses the shortest sequence of map connections, then a shortest reachable local path. It is not a globally distance-optimal road planner. Unsupported maps remain unavailable. The developer teleport mode is intentionally a bypass; normal walking still obeys collision and source gates.
