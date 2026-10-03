# Legacy cave route adaptation

## Herb and doctor

Depends on the reviewed six-cave arrival policy (`7c8cc27`) and final original transaction checks. No arrival policy or source conditions are weakened.

- Herb: public map 200 original portals at (452,162)/(452,163), then 20101–20105. The helper selects the first enabled original entrance; either original entrance remains valid for normal play.
- Doctor: public map 100 original portal (328,633), then 11001–11006. No adult prerequisite is added. The disabled duplicate original destination is not a route grant.
- Both helper modes end outside the public entrance without a cave NPC approach. After actual original passage and walking, a nearby NPC helper leaves the player at the current position, with `has_arrival` and the read-only final `check_action` still required. A player elsewhere inside a legitimate cave must walk onward.
- Herb's public village delivery retains the original medicine condition. Pet capture may keep its existing destinations but cannot establish doctor route eligibility. Event pets, low-level pets, source inventory rules and save rollback remain unchanged.

`legacy_cave_helper.gd` contains only reviewed geometry; it never grants arrival. `tests/support/legacy_cave_route.gd` prepares fixtures through actual `report_position` commands over original collision paths and portals; it never writes arrival state. Tests may still prepare original collection inventory.

Validated headlessly: `original_herb_quest_test`, `original_doctor_quest_test`, `original_doctor_quest_ui_test`, `original_herb_use_test`, `original_herb_use_ui_test`, `quest_helper_ui_test`. Doctor tests retain level boundaries, event-pet rejection, save failure and independent WebSocket device tokens. Helper UI verifies the public entrance first, then real-route setup and nearby original dialogue. Headless UI tests do not verify rendered pixels.

The existing herb automatic runner and the remaining cave adaptations are described below. No new automatic quest is introduced.

## Existing herb automatic runner

The existing job 30 (event 1) now downloads public map 200 and all five original cave maps, approaches the original outdoor entrance, and walks every collision/portal step. The pure plan in `legacy_cave_helper.gd` is not arrival evidence. Every actual move remains observed by the shared authority; field steps still trigger original wild encounters. Stopping retains no cached route authorization; restart re-derives the route, and a process reload starts from the public entrance because arrival evidence is memory-only. The existing adult job and its limits are unchanged.

The old `original_herb_auto_test` restart/stop/save-failure/remote matrix passed in 143.19 seconds (145.93 seconds after incorporating the focused route assertions into the same registered suite) under the normal 180-second shell budget; its finite route step bound is 3000, replacing the old teleport-only 40/60 tick assumptions. A focused source-route scenario also verifies all five floors, a third-floor stop/restart and atomic failed medicine saving. Remote completion waits on the actual final state, not a fixed delay. Doctor auto remains unavailable.

## Goya and wood

Goya helper targets now use the enabled public map 200 entrances (98,425)/(99,425), followed by actual original floors 20401–20406. Existing shell/language and source branch priorities are unchanged; no extra shell gate is added. Wood uses the map 200 entrance (396,821), then 20501–20508; public village exchanges retain their original held-item conditions. Neither chain receives an automatic runner.

`goya_deliveries_quest_test`, `goya_deliveries_ui_test`, `original_wood_quest_test` and `quest_helper_test` pass with original route fixtures. Goya retains free shell/flower branches, both pet reward quantities, lost-letter charm costs, save failure and two-device replay assertions. Wood retains all fifteen payout quantities, low level/full bag/gold limits, explicit NPC context for action-order units, and profile-isolated LAN transactions. Each cave fixture walks original portals; no route grant is fabricated. Unrelated original events are disabled only in isolated test catalogs to avoid repeating unrelated helper work on every walking step.

## Miner contest

The original public root is map 300 (483,196) to 31801 (37,49); the disabled duplicate is not used. Helpers do not move within the cave: they return to the public root without evidence, or preserve the current legitimate nearby position. The sixth-floor script NPC still consumes its original ticket. Ore step display uses only pure geometry, while the actual helper command must pass the same route restrictions.

The source encounter fixture previously called `wild_encounter(31801, Vector2i(24,24))` from the fifth-floor NPC. The original map marks (24,24) blocked; its four neighbours also have no original path. Tests now walk back down the real stairs to (37,48), 435 steps from the rival fixture position, in the same imported encounter area 356. Seed 27 still produces original group 508 / ore enemy 1043. This is no implicit battle teleport and no arrival grant. `original_drops_test` uses an explicit isolated server position at its original wood-drop point; it makes no quest-route claim.

Current arrival integration passes `miner_contest_quest_test`, `miner_contest_ui_test` and `miner_ore_ui_test`, retaining low-level rejection, original ticket/economy, save rollback, source battle retry, strict personal cooldown and two-device replay. The separate backend strict-wild commit `c55fd28548589f2a0e40d91cff98683f99c0e5ad` is now integrated for union verification (local equivalent `ca4ca1c`). The three targeted suites `miner_contest_quest_test`, `miner_ore_ui_test` and `original_drops_test` pass with that implementation; no production command was relaxed for a fixture.

## Saton

The public original root remains south island map 100 (132,421) to 10701 (76,67). The helper now combines shared legitimate-arrival evidence, final read-only action validation, nearby stationary behavior and the existing original connected-component guard. The old component geometry is retained as `Saton.walk_destination` for read-only audit callers. A project placement in any floor/component can only navigate back to the public entrance, never issue a protected guard interaction. Navigation cache state includes route evidence and nearby guard identities, so walking into or out of interaction range updates the helper without rebuilding it at every cell.

`Saton` source guard route, navigation, remote UI and complete GameScene walking tests pass. Navigation retains the component matrix, raw NPC/old helper/two-mode boundary, save rollback, shared-device token handling and independent character guard state. The UI executes two full three-treasure reward/repeat cycles; fixtures walk original paths before each protected interaction. The standalone GameScene walking test now begins outside the public original root, crosses it and all four natural stairs, walks to all three guard neighbours and asserts final server-owned arrival. Public Saton hand-in retains the original item conditions and supplemental END14 decision. Original strict 300-second personal cooldown and source special-AI limitations remain unchanged.

## Final strict-wild union

With original strict-wild commit `c55fd28548589f2a0e40d91cff98683f99c0e5ad` integrated, the three targeted suites passed: miner transactions 8 s, miner ore UI 29 s, original drops 152 s (3/3). The existing herb automatic matrix also passed, but an initial union run took 196.08 s, exceeding the unchanged 180-second shell budget. Its explicit-stop block had run twice identically inside the graceful/crash restart loop. The final fixture retains all 24 restart cases and all 12 distinct stop cases, moves that duplicate block outside the restart-mode loop, and passes in 171.56 s. Measured sections: matrix 93.472 s; total non-UI fixtures 100.779 s; remote UI 68.497 s. No route grant, case coverage or production threshold was relaxed. No runner exception was added for herb.

All six-chain work is complete against this union. The Saton exchange suite additionally passed its public repeat/save-failure/LAN assertions. These are targeted headless results; no full suite or live game process was run, and no new pixel verification is claimed.


## Task-only wild-drop union

Validated against original `6af90df` policy/API and `a30fbde` wild-drop integration, on top of `c55fd28` location authority and `7c8cc27` miner scope. No additional scope snapshot is needed for this miner/wood validation. The existing mine save-failure fixture now walks the original five-floor return to31801(37,48) before opening the source troop; its source map and actual authority agree. Original seed27 ore1043/2534 still survives save rollback/retry exactly once. A separate project-only placement with the same source permit and winning roll may fight/close but receives no2534. No production grant or policy change is used.

Targeted union: miner_contest_quest_test, miner_ore_ui_test and original_drops_test pass (3/3, maximum2 jobs). The strengthened miner-only suite also passes. Ordinary public wood and isolated source-drop assertions remain unchanged. This does not claim full validation of every scope in the shared drop policy.
