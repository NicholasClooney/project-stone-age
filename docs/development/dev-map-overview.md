# Whole-map navigation and developer teleport

Open the map navigator from **游戏助手** (G) → **地图导航**, or from the button below the map window (M). The dropdown browses villages, wilderness and caves without moving the player; building interiors are excluded. This replaces the separate teleport menu: 53 regions remain from 147 imported maps, excluding 94 building interiors. The current interior can still be viewed without appearing as a dropdown choice. The random-encounter toggle also lives here. The view covers the complete current island, including800×1200 Jaruga. Yellow markers are NPCs, cyan markers are original doors/exits, and white marks the player when viewing their map.

## Names on the map

Every marker carries its name, always shown (not only when zoomed in); a legend sits along the bottom of the view. Clicking a name selects its marker like clicking the dot.

- **Places (white names, cyan dots)**: exits to other maps, labelled with the destination map's name from the world manifest (`portals`), e.g. 萨姆吉尔村. Exits with the same name within 12 cells share one marker.
- **Not yet open (grey)**: original exits to maps that are not imported yet (caves, mountain passes, 庄园), from the manifest's `provenance.unsupported_portals`. Their names come from each map's original LS2MAP header, collected into `client/data/exit-names.json` by `tools/build_exit_names.py` (rerun it after `import_world.py` changes the unsupported exits). The floor suffix is dropped (阿布的洞窟地下１楼 → 阿布的洞窟); two Giru dungeons that name only their floor show as 洞窟 地下１楼. Clicking one moves next to the entrance on the current map; the cave itself stays unavailable.
- **Lv.1 pets (green diamond, faint green area outline)**: on the 地点 tab, every encounter area of the map where a pet can be met and caught at Lv.1, from the same wild locations as 宠物大全's 野外出现地点 (`PetEncyclopedia.level_one_areas`). The label lists the pets, e.g. 「邦奇诺 Lv1」, at most three names then 等N种. With a verified landing the marker sits there and clicking checks the encounter area like the Lv.1 宠物 tab; otherwise it sits at the area's centre.
- **Added Lv.1 pets (violet diamond and outline)**: the rare Lv.1 spots this project added (`client/data/rare-encounters.json`, 补充 / 非原版; see [rare Lv.1 encounters](../reverse-engineering/rare-level-one-encounters.md)) get their own label in violet, apart from the area's original Lv.1 pets. The legend names the colour, and the Lv.1 宠物 tab marks those rows 补充 or 非原版.
- **NPCs (yellow)** and, on their tabs, **training spots (orange)** and **Lv.1 宠物 rows (green, same cell joined with 、)**.

Labels are Label nodes (12 px, black outline) built once when the map or tab changes; zoom and pan only move them. Placement is greedy in the order places, pets, closed exits, training, NPCs: right of the marker, then left, above, below, then stacked downwards or upwards until the label clears those already placed; if nothing fits it keeps the first spot. `map_labels_test.gd` covers manifest names on 萨伊那斯, 邦奇诺 on 吉鲁岛, labels at zoom 1 with no overlaps on 萨伊那斯, and clicking a name or a dot to travel.

- **步行** remains available. Click a map point or listed point of interest to walk there. Cross-map navigation follows original portal links and physically walks each segment. The map closes when walking begins.
- **DEV 传送** is the initial default and explicitly bypasses walking and gates. Click to land on nearby walkable ground, excluding NPC cells and automatic portal triggers.
- Scroll to zoom toward the pointer; drag to pan; **居中 / 全图** restores the full extent. Esc closes the navigator.

Walking across islands requires the original reusable undersea permit. At the original guard, navigation opens the existing confirmation dialogue and waits for the player to confirm. It does not silently jump across the checkpoint. Cancelling that dialogue stops the route. Manual movement, another movement target or battle interrupts the route; focus loss does not. After combat, choose a destination again.

The view uses original automap ground colors with gridXright/Ydown orientation. Its cached texture retains one texel per grid cell on both islands and is bounded at1600×1600 for larger future maps; zooming and panning do not recreate thousands of terrain sprites. Only one browsed map's JSON and texture are retained. Clicking unwalkable terrain resolves to a nearby reachable cell for Walk; Teleport searches within32cells and reports failure when no safe ground is available.

## Verification

All runs are muted:

- `travel_router_rules_test.gd`: original graph connectivity, permit enforcement, avoiding unintended doors and restoring navigation collision state.
- `travel_router_test.gd`: remote browsing, pointer-centered zoom, actual shop-door traversal, focus persistence and manual cancellation.
- `dev_map_overview_test.gd`: explicit teleport, real pointer input, map-coordinate conversion and full-island bounds.

Walk routing currently chooses the shortest sequence of map connections, then a shortest reachable local path. It is not a globally distance-optimal road planner. Unsupported maps remain unavailable. The developer teleport mode is intentionally a bypass; normal walking still obeys collision and source gates.
