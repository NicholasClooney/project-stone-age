# Ordinary connected settlement expansion

The importer now selects **103 maps**, up from 54: six additional towns and 43 interiors connected by original unconditional `npcgen_warp` records. The new towns are 霍特尔 (1300), 卡坦 (1400), 塔姆塔姆 (3100), 多多 (3200), 乌鲁力 (3300), 奇喀喀 (3400); 柯奥 (1100) gains its connected interiors. These connect to the already imported full islands 100 and 200. Towns also appear in the developer destination menu and global map.

## Selection and safety

`tools/import_world.py` traverses original warp records only into seven reviewed settlement directories under `gmsv/data/map/sainasu` and `jyaruga`. Directory names alone do not grant access: a connection from an existing selected map is required. Existing permit gate 10202 remains intact. No quest scripts, dungeon transitions, family estates or quiz routes are synthesized. Imported new interiors provide scenery and doors, not restored NPC services or quest behavior.

Each map retains source coordinates, resource collision footprints, music markers and map-source hash. Safe developer spawns remain in an arrival component, avoid doors and NPC cells, and must reach every town exit destination. Missing graphics remain blocked; all 103 current maps have zero missing graphics. The manifest records 468 portal entries and 60 excluded exits with explicit reasons.

Two original source cells have contradictory destinations: island 200 (229,988), and interior 1306 (21,21). All alternatives at these cells remain disabled rather than choosing arbitrarily. Two other portal records retain their pre-existing collision-based disablement (three endpoint findings). Original destination coordinates are never moved to hide inconsistencies. Forest house 3413 consequently remains unavailable through normal walking; developer teleport can inspect its imported scenery. It is not counted as a restored working entrance.

## Rebuild / verify

Use the existing asset setup workflow, or run the world importer with the local original resource root. Imported assets and manifest remain ignored. Run `tools/test_import_world.py` for format, collision, selection, conflicting-warp and reachability contracts; run `scripts/run.sh --headless --script res://tests/world_expansion_test.gd` for muted loading/checkpoint coverage and real bidirectional town transitions.

This is not a claim that all reference maps are restored. Other islands, dungeon corridors, special areas and task-dependent entrances await separate review. Special dungeons, task gates and boss mechanics are deferred with the quest system.

## Reviewed Jyaruga scenic caves (2026-09-30)

The importer now adds 100 connected scenic maps (including the later reviewed floor 21015), using an explicit
`JYARUGA_SCENIC_MAPS` allowlist rather than granting access to the dungeon
directory. All 100 have complete 2.5 graphics and original encounter areas in
`encounters/catalog.json`. They use the `dungeon` kind, which enables ordinary
field encounters. No quest/NPC service implementation is implied.

Fifteen explicitly reviewed `npcgen_warpman` records retain their original
cells and WARP destinations but bypass conditions: 原版需要任务或NPC检查，这里直接开放。
These cover the corridor gate, Strongen mountain spirits, dragon treasure
gate, Karutana entrance and family passageways, Ruri entrance/internal gate,
Hekisei entrance and Suisou entrance/internal gate/return. The manifest records
`gate_source` and `convenience`.

Seven conflicting scenery source cells use one explicitly selected existing
original destination (`SCENIC_DOOR_CHOICES`); other alternatives remain disabled.
Most are adjacent landing duplicates. Ruri 21016 has six distinct destinations
at its single return cell: this scenery convenience fixes its return to the
original 21011 (5,4), without restoring random/quest routing. Existing unrelated
conflicts remain disabled. Two dragon treasure return records remain disabled
because their original endpoints collide; the treasure region can return via
the original island exit.

`verify_jyaruga_world.py` checks zero missing graphics, portal component
reachability from island 200 and return from every imported map's spawn,
original encounter presence and a dedicated web `map-<id>` pack. Every
reachable scenic arrival component must also have an island return path. Same-map
NPC passages connect otherwise separate walkable components; demanding that
a single cardinal flood cover an entire cave would incorrectly reject them.

### Deferred maps

21 original scenic candidates remain deferred after the floor15 review.

- 拉多拉山岭洞窟 20001–20013: source internal stairs exist, but the reviewed
  compiled warp/NPC records contain no entrance from an imported region.
The later Jyaruga interiors review opens 琉璃的洞窟１５楼 21015 through
the original `200/sb_dbt.arg` gate at 21014 (14,14) → 21015 (9,17),
bypassing the original NPC/battle condition for scenery. This leaves 21
previous scenic candidates deferred; no additional doors are invented.
- 拉多拉洞窟山顶 / old 碧青 floors 21103, 21106, 21108–21113 (excluding 21107):
  source map files exist without compiled walking entrance links.
- 哈恩的锻冶场 20508, 沙拉的房间 20608, 审查室 20711, JBA本部 20712,
  special destination 117: outside this scenic batch. Their entrances stay excluded.

No invented entrances or reverse warps are added to make deferred maps appear
restored. Headless checks do not validate rendered pixels.

### Rebuild and verify this batch

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/plan_web_packs.py
.tools/asset-venv/bin/python tools/verify_jyaruga_world.py
.tools/asset-venv/bin/python tools/test_import_world.py
./scripts/run.sh --headless --script res://tests/jyaruga_scenery_test.gd
```

The existing web pack planner discovers new manifest maps automatically; no
change to web storage/asset-packs runtime is needed. Build/upload the planned
packs through the existing web build workflow when publishing.

### Imported map inventory

| Map | ID | Original encounters | Directly opened NPC gate |
| --- | --- | --- | --- |
| 森林洞窟１楼 | 20101 | yes | no |
| 森林洞窟２楼 | 20102 | yes | no |
| 森林洞窟３楼 | 20103 | yes | no |
| 森林洞窟４楼 | 20104 | yes | no |
| 森林洞窟山顶 | 20105 | yes | no |
| 拉多拉的回廊 | 20301 | yes | yes |
| 拉多拉洞窟１楼 | 20302 | yes | no |
| 拉多拉洞窟２楼 | 20303 | yes | no |
| 拉多拉洞窟３楼 | 20304 | yes | no |
| 拉多拉洞窟３楼 | 20305 | yes | no |
| 拉多拉洞窟２楼 | 20306 | yes | no |
| 拉多拉洞窟３楼 | 20307 | yes | no |
| 拉多拉洞窟３楼 | 20308 | yes | no |
| 拉多拉山山顶 | 20309 | yes | no |
| 哥亚山洞窟１楼 | 20401 | yes | no |
| 哥亚山洞窟２楼 | 20402 | yes | no |
| 哥亚山洞窟３楼 | 20403 | yes | no |
| 哥亚山洞窟４楼 | 20404 | yes | no |
| 哥亚山洞窟５楼 | 20405 | yes | no |
| 哥亚山的洞窟山顶 | 20406 | yes | no |
| 阿鲁姆山的洞窟地下１楼 | 20501 | yes | no |
| 阿鲁姆山的洞窟地下２楼 | 20502 | yes | no |
| 阿鲁姆山的洞窟地下３楼 | 20503 | yes | no |
| 阿鲁姆山的洞窟地下４楼 | 20504 | yes | no |
| 阿鲁姆山的洞窟地下５楼 | 20505 | yes | no |
| 阿鲁姆山的洞窟地下６楼 | 20506 | yes | no |
| 阿鲁姆山的洞窟地下７楼 | 20507 | yes | no |
| 强恩一族的洞窟１楼 | 20601 | yes | no |
| 强恩一族的洞窟２楼 | 20602 | yes | no |
| 强恩一族的洞窟３楼 | 20603 | yes | no |
| 强恩一族的洞窟４楼 | 20604 | yes | yes |
| 强恩一族的洞窟５楼 | 20605 | yes | yes |
| 强恩一族的洞窟６楼 | 20606 | yes | yes |
| 强恩一族的洞窟７楼 | 20607 | yes | yes |
| 拉多拉的大洞窟１楼 | 20701 | yes | no |
| 拉多拉的大洞窟２楼 | 20702 | yes | no |
| 拉多拉的大洞窟３楼 | 20703 | yes | no |
| 拉多拉的大洞窟３楼 | 20704 | yes | no |
| 拉多拉的大洞窟３楼 | 20705 | yes | no |
| 拉多拉的大洞窟４楼 | 20706 | yes | no |
| 拉多拉的大洞窟５楼 | 20707 | yes | no |
| 拉多拉的大洞窟６楼 | 20708 | yes | no |
| 拉多拉的大洞窟７楼 | 20709 | yes | no |
| 拉多拉的大洞窟８楼 | 20710 | yes | no |
| 龙的巢穴１楼 | 20801 | yes | no |
| 龙的巢穴２楼 | 20802 | yes | no |
| 龙的巢穴３楼 | 20803 | yes | no |
| 龙的巢穴４楼 | 20804 | yes | no |
| 龙的巢穴５楼 | 20805 | yes | no |
| 龙的巢穴６楼 | 20806 | yes | no |
| 龙的巢穴７楼 | 20807 | yes | yes |
| 卡鲁它那的洞窟１楼 | 20901 | yes | yes |
| 卡鲁它那的洞窟２楼 | 20902 | yes | yes |
| 卡鲁它那的洞窟２楼 | 20903 | yes | yes |
| 琉璃的洞窟１楼 | 21001 | yes | yes |
| 琉璃的洞窟２楼 | 21002 | yes | no |
| 琉璃的洞窟３楼 | 21003 | yes | yes |
| 琉璃的洞窟４楼 | 21004 | yes | no |
| 琉璃的洞窟５楼 | 21005 | yes | no |
| 琉璃的洞窟６楼 | 21006 | yes | no |
| 琉璃的洞窟７楼 | 21007 | yes | no |
| 琉璃的洞窟８楼 | 21008 | yes | no |
| 琉璃的洞窟９楼 | 21009 | yes | no |
| 琉璃的洞窟１０楼 | 21010 | yes | no |
| 琉璃的洞窟１１楼 | 21011 | yes | no |
| 琉璃的洞窟１２楼 | 21012 | yes | no |
| 琉璃的洞窟１３楼 | 21013 | yes | no |
| 琉璃的洞窟１４楼 | 21014 | yes | no |
| 琉璃的洞窟１２楼 | 21016 | yes | no |
| 碧青的洞窟地下１楼 | 21201 | yes | yes |
| 碧青的洞窟地下２楼 | 21202 | yes | no |
| 碧青的洞窟地下３楼 | 21203 | yes | no |
| 碧青的洞窟地下４楼 | 21204 | yes | no |
| 碧青的洞窟地下５楼 | 21205 | yes | no |
| 碧青的洞窟地下６楼 | 21206 | yes | no |
| 碧青的洞窟地下７楼 | 21207 | yes | no |
| 碧青的洞窟地下８楼 | 21208 | yes | no |
| 碧青的洞窟地下９楼 | 21209 | yes | no |
| 碧青的洞窟地下１０楼 | 21210 | yes | no |
| 碧青的洞窟地下１１楼 | 21211 | yes | no |
| 碧青的洞窟地下１２楼 | 21212 | yes | no |
| 碧青的洞窟地下１３楼 | 21213 | yes | no |
| 碧青的洞窟地下１４楼 | 21214 | yes | no |
| 碧青的洞窟地下１５楼 | 21215 | yes | no |
| 水苍的洞窟 地下1楼 | 21301 | yes | yes |
| 水苍的洞窟 地下2楼 | 21302 | yes | no |
| 水苍的洞窟 地下3楼 | 21303 | yes | no |
| 水苍的洞窟 地下4楼 | 21304 | yes | no |
| 水苍的洞窟 地下5楼 | 21305 | yes | no |
| 水苍的洞窟 地下6楼 | 21306 | yes | no |
| 水苍的洞窟 地下7楼 | 21307 | yes | no |
| 水苍的洞窟 地下8楼 | 21308 | yes | yes |
| 水苍的洞窟 地下9楼 | 21309 | yes | no |
| 水苍的洞窟 地下10楼 | 21310 | yes | no |
| 水苍的洞窟 地下11楼 | 21311 | yes | no |
| 水苍的洞窟 地下12楼 | 21312 | yes | no |
| 水苍的洞窟 地下13楼 | 21313 | yes | no |
| 水苍的洞窟 地下14楼 | 21314 | yes | no |
| 水苍的洞窟 地下15楼 | 21315 | yes | no |
