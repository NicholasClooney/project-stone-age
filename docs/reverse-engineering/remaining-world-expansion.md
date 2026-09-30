# Remaining original world expansion

Reviewed region allowlists live in `tools/world_regions/*.json`. The importer
reads original compiled doors, recursive NPC files and `mapwarp.txt`
`NONE:NULL` records only for those maps. NPC/battle gates are enabled only
through exact reviewed argument paths. Original source/target cells and
direction are preserved; no missing reverse door is fabricated. Conditions
are bypassed as a scenery convenience, not a restored quest or boss.

## Sainasu

Adds 67 maps (313 total at this commit), including Kuruku village, its connected
ordinary interiors, the three-floor road, the connected upper great pit, East
Kuruku mine, Genou, illusion cave, thief cave/base, Abu house, Kuo mountain cave
and laboratory, and the extra underwater ceremony room. Existing underwater
passage 10201–10203 remains; its passage permit gate stays enforced.

Two duplicated island entrance cells use a reviewed existing landing:
100(237,445) ->10901(25,49), and 100(328,633) ->11001(0,43).
Other original alternatives remain recorded but disabled. Nine exact NPC/boss
argument scripts bypass conditions, including the two thief-base guards and
Genou floor14 guardian. No bosses, services or ceremony events are implemented.

Deferred candidates have source map files but no reviewed incoming connection:
1209 (Kuruku convenience store), 10301–10308 (Kuo cave), 10801–10809
(Hotoru cave), and 10902–10911 (great pit underground branch). The remaining
great pit upstairs floors10912–10918 are connected and imported. No entrance
is invented for these gaps.

The encounter-area column means an original catalog row exists; the random
encounter column additionally requires a positive original probability and
troop groups. Town/service records can exist with zero probability.

| Map | ID | Encounter area | Random encounters | NPC gate directly opened |
| --- | --- | --- | --- | --- |
| 阿布的独栋房屋 | 101 | yes | no | no |
| 柯尔克村 | 1200 | yes | no | no |
| 柯尔克的武器店 | 1201 | no | no | no |
| 柯尔克的道具店 | 1202 | no | no | no |
| 柯尔克的宠物店 | 1203 | no | no | no |
| 柯尔克的肉店 | 1204 | no | no | no |
| 柯尔克的医院 | 1205 | no | no | no |
| 柯尔克的村长家 | 1206 | no | no | no |
| 柯尔克的石屋 | 1210 | no | no | no |
| 柯尔克坑道管理事务所 | 1212 | no | no | no |
| 往柯尔克的道路１楼 | 10101 | yes | yes | no |
| 往柯尔克的道路２楼 | 10102 | yes | yes | no |
| 往柯尔克的道路３楼 | 10103 | yes | yes | no |
| 海底通路地下１楼 | 10201 | yes | yes | no |
| 海底通路地下２楼 | 10202 | yes | yes | yes |
| 海底通路地下１楼 | 10203 | yes | yes | no |
| 海底通路地下２楼 | 10204 | yes | yes | yes |
| 迷幻洞窟 | 10402 | yes | yes | yes |
| 迷幻洞窟 | 10403 | yes | yes | no |
| 迷幻洞窟 | 10404 | yes | yes | no |
| 迷幻洞窟 | 10405 | yes | yes | no |
| 迷幻洞窟 | 10406 | yes | yes | no |
| 迷幻洞窟 | 10407 | yes | yes | no |
| 迷幻洞窟最底层 | 10408 | yes | no | no |
| 东柯尔克的坑道１楼 | 10601 | yes | yes | yes |
| 东柯尔克的坑道２楼 | 10602 | yes | yes | no |
| 东柯尔克的坑道３楼 | 10603 | yes | yes | no |
| 东柯尔克的坑道４楼 | 10604 | yes | yes | no |
| 东柯尔克的坑道５楼 | 10605 | yes | yes | no |
| 盗贼的洞窟地下１楼 | 10701 | yes | yes | no |
| 盗贼的洞窟地下２楼 | 10702 | yes | yes | no |
| 盗贼的洞窟地下３楼 | 10703 | yes | yes | no |
| 盗贼的洞窟地下４楼 | 10704 | yes | yes | no |
| 盗贼的洞窟地下５楼 | 10705 | yes | yes | no |
| 柯尔克的大坑道１楼 | 10901 | yes | yes | no |
| 柯尔克的大坑道２楼 | 10912 | yes | yes | no |
| 柯尔克的大坑道３楼 | 10913 | yes | yes | no |
| 柯尔克的大坑道４楼 | 10914 | yes | yes | no |
| 柯尔克的大坑道５楼 | 10915 | yes | yes | no |
| 柯尔克的大坑道６楼 | 10916 | yes | yes | no |
| 柯尔克的大坑道７楼 | 10917 | yes | yes | no |
| 柯尔克的大坑道８楼 | 10918 | yes | yes | no |
| 柯奥山的小洞窟１楼 | 11001 | yes | yes | no |
| 柯奥山的小洞窟２楼 | 11002 | yes | yes | no |
| 柯奥山的小洞窟３楼 | 11003 | yes | yes | no |
| 柯奥山的小洞窟４楼 | 11004 | yes | yes | no |
| 柯奥山的小洞窟５楼 | 11005 | yes | yes | no |
| 博士的研究所 | 11006 | yes | no | no |
| 盗贼的基地地下１楼 | 11101 | yes | yes | yes |
| 盗贼的基地地下２楼 | 11102 | yes | yes | no |
| 盗贼的基地地下３楼 | 11103 | yes | yes | no |
| 盗贼的基地地下４楼 | 11104 | yes | yes | no |
| 盗贼的基地地下５楼 | 11105 | yes | yes | no |
| 盗贼的基地地下６楼 | 11106 | yes | yes | no |
| 盗贼的基地最底层 | 11107 | yes | no | yes |
| 玄黄的洞窟地下１楼 | 11201 | yes | yes | yes |
| 玄黄的洞窟地下２楼 | 11202 | yes | yes | no |
| 玄黄的洞窟地下３楼 | 11203 | yes | yes | no |
| 玄黄的洞窟地下４楼 | 11204 | yes | yes | no |
| 玄黄的洞窟地下５楼 | 11205 | yes | yes | no |
| 玄黄的洞窟地下６楼 | 11206 | yes | yes | yes |
| 玄黄的洞窟地下７楼 | 11207 | yes | yes | no |
| 玄黄的洞窟地下８楼 | 11208 | yes | yes | no |
| 玄黄的洞窟地下９楼 | 11209 | yes | yes | no |
| 玄黄的洞窟地下１０楼 | 11210 | yes | yes | no |
| 玄黄的洞窟地下１１楼 | 11211 | yes | yes | no |
| 玄黄的洞窟地下１２楼 | 11212 | yes | yes | no |
| 玄黄的洞窟地下１３楼 | 11213 | yes | yes | no |
| 玄黄的洞窟地下１４楼 | 11214 | yes | yes | yes |
| 玄黄的洞窟地下１５楼 | 11215 | yes | no | yes |

## Rebuild / verify

After each region commit, main must re-run the world importer,
`tools/plan_web_packs.py`, `tools/build_exit_names.py`, and the headless editor
import. `tools/verify_world_regions.py --region <region>` checks zero missing
graphics, original encounters, dedicated web map packs and walking-component
travel from/return to an existing island. It also checks every reachable arrival
component for a return path. The headless suites do not verify rendered pixels.

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/plan_web_packs.py
python3 tools/build_exit_names.py
./scripts/run.sh --headless --editor --import --quit
.tools/asset-venv/bin/python tools/verify_world_regions.py --region sainasu
```
