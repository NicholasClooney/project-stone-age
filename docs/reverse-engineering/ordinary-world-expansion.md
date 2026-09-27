# Ordinary connected settlement expansion

The importer now selects **103 maps**, up from 54: six additional towns and 43 interiors connected by original unconditional `npcgen_warp` records. The new towns are 霍特尔 (1300), 卡坦 (1400), 塔姆塔姆 (3100), 多多 (3200), 乌鲁力 (3300), 奇喀喀 (3400); 柯奥 (1100) gains its connected interiors. These connect to the already imported full islands 100 and 200. Towns also appear in the developer destination menu and global map.

## Selection and safety

`tools/import_world.py` traverses original warp records only into seven reviewed settlement directories under `gmsv/data/map/sainasu` and `jyaruga`. Directory names alone do not grant access: a connection from an existing selected map is required. Existing permit gate 10202 remains intact. No quest scripts, dungeon transitions, family estates or quiz routes are synthesized. Imported new interiors provide scenery and doors, not restored NPC services or quest behavior.

Each map retains source coordinates, resource collision footprints, music markers and map-source hash. Safe developer spawns remain in an arrival component, avoid doors and NPC cells, and must reach every town exit destination. Missing graphics remain blocked; all 103 current maps have zero missing graphics. The manifest records 468 portal entries and 60 excluded exits with explicit reasons.

Two original source cells have contradictory destinations: island 200 (229,988), and interior 1306 (21,21). All alternatives at these cells remain disabled rather than choosing arbitrarily. Two other portal records retain their pre-existing collision-based disablement (three endpoint findings). Original destination coordinates are never moved to hide inconsistencies. Forest house 3413 consequently remains unavailable through normal walking; developer teleport can inspect its imported scenery. It is not counted as a restored working entrance.

## Rebuild / verify

Use the existing asset setup workflow, or run the world importer with the local original resource root. Imported assets and manifest remain ignored. Run `tools/test_import_world.py` for format, collision, selection, conflicting-warp and reachability contracts; run `scripts/run.sh --headless --script res://tests/world_expansion_test.gd` for muted loading/checkpoint coverage and real bidirectional town transitions.

This is not a claim that all reference maps are restored. Other islands, dungeon corridors, special areas and task-dependent entrances await separate review. Special dungeons, task gates and boss mechanics are deferred with the quest system.
