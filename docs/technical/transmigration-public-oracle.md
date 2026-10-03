# Four-spirit public catalogue oracle

This test-only union is reviewed from committed manifests, pinned original GB18030 scripts/create records and the independent source fixtures. Expected NPCs are frozen before importing assets; neither the running catalogue nor an importer exports expected values. Production modules and gameplay policy are unchanged by this test commit.

| Chain | Reviewed feature | Source increment | Instances / declared items |
|---|---|---|---|
| Earth | `861809d40714d99833e0637ea1f3e1433ff1cea7` | `c81b017bc8073f5ee420f5ebe9b6cbed63cb53d3` | 11 / 99 |
| Wind | `efaeddb9327378e58d9527f1b2f72940d51703cf` | same feature | 11 / 27 |
| Water | `9a4d10477ff1f34cca70ebf95aa1ab7dabbca0ff` | `1825a7e`, `188f648`, `0bb3ccf` | 15 / 55; 13 reviewed drops |
| Fire | `3932b4359f40d184171cd37b8a97c7c182804c40` | `6d98ce6b1d0c0e04303dc32d13e1dfe941f53bbd` | 19 / 42 |

The exact catalogue contains **297 NPC instances and 338 item IDs**: all prior242 identities and prior branch fields remain, plus55 new instances. Wind contributes10 new instances because `sainasu/event/event12@11107:24:6` remains the single Munde NPC, with source branches0–4 in original order and the complete original branch0 unchanged. All old groups remain. Every enabled descriptor is checked against its own frozen group; extra or missing IDs fail equality.

Item declarations across manifests total382;44 repeated declarations represent41 IDs shared between manifests. The338-ID set only deduplicates catalogue definitions. It does not deduplicate any reward pool or alter slot order/weights. Wind's approved branch0 condition normalization is checked alongside the complete `source_condition`; all three UID-selection branches retain exact `source_actions`, including weighted random rewards.

The active projection is **296 fixed catalogue NPCs plus two independent Charm services =298**. The remaining area instance, `seimu/event/event02_1@100:230:180:area:525:200`, stays absent until placed. Its explicit test override at map100(230,180) is walkable; placement produces299 active entries including services, and hiding it returns exactly298. A region NPC is not silently dropped from the297-instance catalogue.

Water's two original adult-gated entrances remain enabled through event4 when event46 is disabled. Closing the four spirit descriptors must preserve the shared Munde NPC. Both helper modes, raw NPC calls and old cached step requests remain denied for spirit-only NPCs. Production checks precede fixture mutation: no `777/ten.arg`, no transmigration command, no registered third-stage entrance, no300→32001 convenience portal, and32021 remains developer-only. Event47 is the unrelated original quiz, not proof about rebirth settlement.

## Transaction fixture and route coverage

`transmigration_foundation_test.fixed_troops` isolates source battle transactions by moving only its private NPC copies to public map1000(55,92). IDs, source scripts, branches, enemy order and actions stay unchanged. It checks all ten enemy IDs, real battle/save failure rollback/retry, personal strict>180-second cooldown where applicable, original victory Warp and replay rejection. This fixture does **not** prove legitimate arrival at the original positions and grants no route evidence or production exemption.

A separate fresh production Backend checks every original instance's map/cell, rejects project-placement dialogue and verifies `check_action(...,"BATTLE")` denies authority. Static public equality independently locks full original bindings and branches. Actual successful route coverage is:

| Original guard instances | Actual route success suite | Project-placement rejection |
|---|---|---|
| `200/sb_dtp.arg@21009:43:48`, `200/sb_dbt.arg@21014:14:14` | `transmigration_earth_route_test`; `quest_arrival_earth_test` | `transmigration_earth_arrival_test`; foundation per-instance check |
| `200/sb_mzl.arg@21208:30:16`, `200/sb_mzn.arg@21214:30:40` | `transmigration_water_test.guards_and_gates` via real `WaterRoute.cave`; both saved original battles | foundation per-instance check |
| `300/sb_hba7.arg@30007:16:11`, `300/sb_hba9.arg@30009:39:20`, `300/sb_hpa.arg@30016:26:66` | `transmigration_fire_test.guards_and_navigation` uses original gates and `source_talk` walking driver for all three | foundation per-instance check |
| `100/sb_kbu.arg@11208:26:40`, `100/sb_kbu.arg@11208:42:38`, `100/sb_kgi.arg@11214:41:36` | `transmigration_wind_ui_test` full original route; observed real clicks on both middle instances and summit twice | foundation per-instance check |

The route suites already passed with their chain deliveries. This oracle increment reruns affected foundation/public tests, not all four routes. The local verification integration includes the reviewed fire arrival policy `2618375`, in addition to the existing earth/water/wind policies; no route check is replaced with an unprotected production cave.

## Directed verification and asset import

Run `tools/test_transmigration_foundation.py` (8 tests), `tools/test_transmigration_assets.py` (3 tests), and the Godot suites `original_quests_test`, `transmigration_foundation_test`, `transmigration_navigation_test`. Existing registrations remain unchanged. The latter still tests isolated helper dispatch and geometric boundaries; it does not claim to reproduce each production route.

Only a worktree with an independent legacy-assets directory may run:

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/palette_images.py
python3 tools/split_manifests.py
./scripts/run.sh --headless --editor --import --quit
python3 tools/plan_web_packs.py
```

The isolated integration produced450 maps,1572 portals and4751 images, with297 quest NPCs/320 items matching the original four-chain oracle; the later Dream repeat reward integration expands the item union to338. Assets, original archives and rendered screenshots are not committed. This increment changes test data and assertions only; no new graphical verification is needed.

## Dream repeat reward integration correction

The `integrate/stage-two` baseline `92f0ec0` also includes `cfdb568` (original repeatable Dream rewards), which the first four-chain fixture omitted. Both pinned scripts add original zero-based branch4: `event01_1` at public6000 requests2603 with the complete original OR; both `event01_2` instances at41/42 consume2603 and draw from the exact20 source slots. Existing branch priority and all preceding branches stay unchanged; the repeat branch has event=-1 and no completion flag action.

The frozen `reviewed_source_extensions.dream-repeat` stores both exact SHA256 values, the feature commit, original20-slot sequence and18 newly unique item IDs. The other two reward IDs (646,11814) were already in the four-chain item union. This is338 item definitions and still297 NPC instances; there is no reward-pool deduplication. A directed Python assertion reads pinned GB18030 source bytes independently of the importer and checks all three branch4 instances, ordering and exact full manifest item union. Runtime public equality still rejects missing/extra IDs. Migration assertions and production code are outside this correction.
