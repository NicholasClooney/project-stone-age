# Legacy cave route adaptation

## Herb and doctor

Depends on the reviewed six-cave arrival policy (`7c8cc27`) and final original transaction checks. No arrival policy or source conditions are weakened.

- Herb: public map 200 original portals at (452,162)/(452,163), then 20101–20105. The helper selects the first enabled original entrance; either original entrance remains valid for normal play.
- Doctor: public map 100 original portal (328,633), then 11001–11006. No adult prerequisite is added. The disabled duplicate original destination is not a route grant.
- Both helper modes end outside the public entrance without a cave NPC approach. After actual original passage and walking, a nearby NPC helper leaves the player at the current position, with `has_arrival` and the read-only final `check_action` still required. A player elsewhere inside a legitimate cave must walk onward.
- Herb's public village delivery retains the original medicine condition. Pet capture may keep its existing destinations but cannot establish doctor route eligibility. Event pets, low-level pets, source inventory rules and save rollback remain unchanged.

`legacy_cave_helper.gd` contains only reviewed geometry; it never grants arrival. `tests/support/legacy_cave_route.gd` prepares fixtures through actual `report_position` commands over original collision paths and portals; it never writes arrival state. Tests may still prepare original collection inventory.

Validated headlessly: `original_herb_quest_test`, `original_doctor_quest_test`, `original_doctor_quest_ui_test`, `original_herb_use_test`, `original_herb_use_ui_test`, `quest_helper_ui_test`. Doctor tests retain level boundaries, event-pet rejection, save failure and independent WebSocket device tokens. Helper UI verifies the public entrance first, then real-route setup and nearby original dialogue. Headless UI tests do not verify rendered pixels.

The existing herb automatic runner and its restart matrix are a subsequent adaptation; this first slice does not claim that old automatic cave teleportation works with the route policy. Goya, wood, Saton and miner helper adaptations are also subsequent slices. No new automatic quest is introduced.

## Existing herb automatic runner

The existing job 30 (event 1) now downloads public map 200 and all five original cave maps, approaches the original outdoor entrance, and walks every collision/portal step. The pure plan in `legacy_cave_helper.gd` is not arrival evidence. Every actual move remains observed by the shared authority; field steps still trigger original wild encounters. Stopping retains no cached route authorization; restart re-derives the route, and a process reload starts from the public entrance because arrival evidence is memory-only. The existing adult job and its limits are unchanged.

The old `original_herb_auto_test` restart/stop/save-failure/remote matrix passed in 143.19 seconds (145.93 seconds after incorporating the focused route assertions into the same registered suite) under the normal 180-second shell budget; its finite route step bound is 3000, replacing the old teleport-only 40/60 tick assumptions. A focused source-route scenario also verifies all five floors, a third-floor stop/restart and atomic failed medicine saving. Remote completion waits on the actual final state, not a fixed delay. Doctor auto remains unavailable.

## Goya and wood

Goya helper targets now use the enabled public map 200 entrances (98,425)/(99,425), followed by actual original floors 20401–20406. Existing shell/language and source branch priorities are unchanged; no extra shell gate is added. Wood uses the map 200 entrance (396,821), then 20501–20508; public village exchanges retain their original held-item conditions. Neither chain receives an automatic runner.

`goya_deliveries_quest_test`, `goya_deliveries_ui_test`, `original_wood_quest_test` and `quest_helper_test` pass with original route fixtures. Goya retains free shell/flower branches, both pet reward quantities, lost-letter charm costs, save failure and two-device replay assertions. Wood retains all fifteen payout quantities, low level/full bag/gold limits, explicit NPC context for action-order units, and profile-isolated LAN transactions. Each cave fixture walks original portals; no route grant is fabricated. Unrelated original events are disabled only in isolated test catalogs to avoid repeating unrelated helper work on every walking step.
