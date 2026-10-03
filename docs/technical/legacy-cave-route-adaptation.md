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
