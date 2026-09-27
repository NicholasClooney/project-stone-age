# M005 — Four villages and the connecting world

This restoration comes before the approved progression, pet management, multi-enemy combat, combat outcomes and pet skills slices.

## World scope

- Original Samgir (1000), Marinas (2000), Jaja (3000) and Karutana (4000), with their village-linked interiors.
- Complete Sainas (100, 800×800) and Jyaruga (200, 800×1200) wilderness, replacing the original 96×96 prototype crop. Existing saved wilderness positions already use original coordinates and remain valid.
- The original island connection: Sainas → Kuo (1100) → undersea passage (10201, 10202, 10203) → Jyaruga. There is no invented direct island warp.
- 54 maps and 235 enabled original portal cells; two inconsistent Jaja edge links remain disabled with adjacent working lanes.
- Original entrance/exit coordinates, collision metadata, map-window colors and source map music. A few inconsistent source portal cells are disabled and recorded by the importer; adjacent valid gate cells remain available.
- The undersea pass gate retains its reusable pass requirement. Original vendors in Kuo and Karutana sell item 2422 for 200 stone. Optional branches and their quest gates are not automatically opened.

## Visiting and playing

Use **DEV → 传送地点** to visit any of the four starting villages, either wilderness, Kuo or the connecting cave floors. This is explicitly a developer shortcut; normal movement still follows original doors and map exits. Toggle **野外随机遇敌** off in that menu for uninterrupted exploration. Teleporting is unavailable during battle or modal dialogue.

Nearby original scenery is instantiated around the camera and remains Y-sorted with characters. Full-map collision and navigation remain available. Unloaded scenery does not remove collision. Loading a map retains the camera zoom and uses the existing transition effect; developer teleport switches immediately.

## Scope boundaries

This is world restoration, not completion of every village service and quest. Existing Samgir gameplay remains; 40 ordinary residents use original dialogue. Event-driven NPCs, other shop inventories, healers, save-point systems, transports and regional encounter tables require their own source-backed slices. Wilderness encounters currently use the existing MVP species and rules. Original asset versions and source data differ; provenance records any discrepancies rather than inventing replacements.

## Evidence and verification

`tools/import_world.py` reads the pinned `chenmingbiao/stone-age` LS2MAP files and `npc/genout/*.create` warp definitions. The generated, ignored `world/manifest.json` records map hashes, dimensions, selected portals, music, missing graphics, disabled links and connectivity checks. Resource decoding uses the existing local 2.5 client archive.

`world_expansion_test.gd` loads the supported maps, checks safe coordinates and save acceptance, verifies bounded scenery, uses real village portal transitions, and exercises the developer menu. `travel_gate_test.gd` checks purchase, retained pass and save validation. Run all checks silently through `scripts/test.sh`; inspect rendered village/cave captures before committing.

Original map rendering evidence: client `system/map.cpp:3896` places nonzero-hit priority-3 objects behind characters. Bridge scenery now follows this rule; other scenery retains Y sorting. The bottom status label keeps an explicit Chinese font when reparented above combat.
