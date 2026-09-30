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

## Giru

Adds **83 connected maps**, based on the imported-map component verification report:
16 crimson cave maps, eight East Giru mountain maps, five North Giru road maps,
seven unnamed passage maps (30301–30307), three North Giru mountain maps,
11 Banamu cave maps, three unnamed passage maps (30701–30703), three Gaturo
cave/room maps, three Meruna cave/room maps, four underwater passage maps,
three direction shrine maps, six Asumaru mine maps, and 11 quarry/knowledge/spirit
maps. The 303 and 307 passage groups retain their original generic floor names;
no cave affiliation is invented. Existing villages and island maps are retained.

Reviewed quest/NPC/battle gates directly open as a scenery convenience. Their
original direction, source cells and destination coordinates are preserved;
quests, bosses and NPC services are not implemented. The table records each
exact relaxed gate argument path, rather than claiming quest completion.
Original encounter-area records and actual random encounters remain distinct.

The following 27 candidates remain unavailable:

- 31604–31610 (direction shrine): an arrival walking component lacks a verified
  return to the island; map-level graph connectivity alone is insufficient.
- 31201–31205 (fallen mine): original island cell 300(444,494) targets both
  31201(23/24,49) and 31205(20,11). This is a cross-floor conflict, so no arbitrary
  destination is chosen and no replacement entrance is invented.
- 30017 (volcanic fissure passage): header dimensions are 49×99, with 596 trailing
  bytes. Original server readers use the header-sized layers; dimensions must
  not be guessed as 50×100. Only an outgoing door to 30008 is known, with no
  incoming entrance, so the map stays deferred.
- 30022–30026 (crystal cave): all missing graphics can be recovered from 8.0,
  but no original incoming entrance is known. Recoverable art does not authorize
  opening an unconnected map.
- 5107, 9355–9357 (Dana rooms/passages) and 30901–30905: no reachable original
  incoming doors. 9357 only has an entrance from the unavailable 9356.

Two source files for 31001 differ only in name bytes; geometry after byte 40
matches the 2.5 client. The reviewed `giiru/dan_3-10-01` source preserves the
Gaturo name without treating the duplicate as a geometry conflict.

The original island 400 also needs logical tile **15401** from the 8.0 fallback.
Fallback bitmap filenames use a separate namespace so 8.0 bitmap IDs cannot
silently overwrite 2.5 images. This is a graphics recovery detail, not new island
content. Verification checks graphics references and walking components; no
rendered-pixel comparison has been performed.

| Map | ID | Encounter area | Random encounters | NPC gate directly opened (argument paths) |
| --- | --- | --- | --- | --- |
| 深红的洞窟地下１楼 | 30001 | yes | yes | `genout/wpm_30502_45_41` |
| 深红的洞窟地下２楼 | 30002 | yes | yes | no |
| 深红的洞窟地下３楼 | 30003 | yes | yes | no |
| 深红的洞窟地下４楼 | 30004 | yes | yes | no |
| 深红的洞窟地下５楼 | 30005 | yes | yes | no |
| 深红的洞窟地下６楼 | 30006 | yes | yes | no |
| 深红的洞窟地下７楼 | 30007 | yes | yes | `300/sb_hba7.arg` |
| 深红的洞窟地下８楼 | 30008 | yes | yes | `300/sb_hba7.arg`, `300/sb_hba9.arg` |
| 深红的洞窟地下７楼 | 30009 | yes | yes | `300/sb_hba9.arg` |
| 深红的洞窟地下６楼 | 30010 | yes | yes | no |
| 深红的洞窟地下５楼 | 30011 | yes | yes | no |
| 深红的洞窟地下４楼 | 30012 | yes | yes | no |
| 深红的洞窟地下３楼 | 30013 | yes | yes | no |
| 深红的洞窟地下２楼 | 30014 | yes | yes | no |
| 深红的洞窟地下１楼 | 30015 | yes | yes | `genout/wpm_30503_26_5` |
| 深红的洞窟地下９楼 | 30016 | yes | no | `300/sb_hpa.arg` |
| 东吉鲁山岭１楼 | 30101 | yes | yes | no |
| 东吉鲁山岭２楼 | 30102 | yes | yes | no |
| 东吉鲁山岭地下１楼 | 30103 | yes | yes | no |
| 东吉鲁山岭１楼 | 30104 | yes | yes | no |
| 东吉鲁山岭１楼 | 30105 | yes | yes | no |
| 东吉鲁山岭１楼 | 30106 | yes | yes | no |
| 东吉鲁山岭地下１楼 | 30107 | yes | yes | no |
| 东吉鲁山岭１楼 | 30108 | yes | yes | no |
| 北吉鲁的通路地下１楼 | 30201 | yes | yes | no |
| 北吉鲁的通路地下2楼 | 30202 | yes | yes | no |
| 北吉鲁的通路地下３楼 | 30203 | yes | yes | no |
| 北吉鲁的通路地下２楼 | 30204 | yes | yes | no |
| 北吉鲁的通路地下１楼 | 30205 | yes | yes | no |
| 地下1楼 | 30301 | yes | yes | `genout/wpm_300_247_222` |
| 地下2楼 | 30302 | yes | yes | no |
| 地下1楼 | 30303 | yes | yes | no |
| 地下2楼 | 30304 | yes | yes | no |
| 地下3楼 | 30305 | yes | yes | no |
| 地下2楼 | 30306 | yes | yes | no |
| 地下1楼 | 30307 | yes | yes | `genout/wpm_300_182_162` |
| 北吉鲁山岭地下１楼 | 30401 | yes | yes | no |
| 北吉鲁山岭地下２楼 | 30402 | yes | yes | no |
| 北吉鲁山岭地下１楼 | 30403 | yes | yes | no |
| 巴那姆的洞窟地下１楼 | 30501 | yes | yes | no |
| 巴那姆的洞窟地下２楼 | 30502 | yes | yes | `genout/wpm_30502_45_41` |
| 巴那姆的洞窟地下２楼 | 30503 | yes | yes | `genout/wpm_30503_26_5` |
| 巴那姆的洞窟地下１楼 | 30504 | yes | yes | no |
| 巴那姆的洞窟１楼 | 30505 | yes | yes | no |
| 巴那姆的洞窟地下１楼 | 30506 | yes | yes | no |
| 巴那姆的洞窟地下２楼 | 30507 | yes | yes | no |
| 巴那姆的洞窟地下３楼 | 30508 | yes | yes | no |
| 巴那姆的洞窟地下２楼 | 30509 | yes | yes | no |
| 巴那姆的洞窟地下３楼 | 30510 | yes | yes | no |
| 巴那姆的洞窟地下３楼 | 30511 | yes | yes | no |
| 地下１楼 | 30701 | yes | yes | no |
| 地下２楼 | 30702 | yes | yes | no |
| 地下１楼 | 30703 | yes | yes | no |
| 加特洛的洞窟１楼 | 31001 | yes | no | no |
| 加特洛的洞窟２楼 | 31002 | yes | no | no |
| 族长的房间 | 31003 | yes | no | no |
| 美鲁娜的洞窟１楼 | 31101 | yes | no | no |
| 美鲁娜的洞窟２楼 | 31102 | yes | no | no |
| 族长的房间 | 31103 | yes | no | no |
| 吉鲁的海底通路 | 31301 | yes | yes | no |
| 吉鲁的海底通道 | 31302 | yes | yes | no |
| 奇努伊的海底通路 | 31401 | yes | yes | no |
| 奇努伊的海底通路 | 31501 | yes | yes | no |
| 方位的祠 | 31601 | yes | yes | no |
| 方位的祠 | 31602 | yes | yes | no |
| 方位的祠 | 31603 | yes | no | `300/sb_4sinh3.arg`, `300/sb_4sink3.arg`, `300/sb_4sinm3.arg`, `300/sb_4sint3.arg` |
| 阿斯玛鲁矿山１楼 | 31801 | yes | yes | no |
| 阿斯玛鲁矿山２楼 | 31802 | yes | yes | no |
| 阿斯玛鲁矿山３楼 | 31803 | yes | yes | no |
| 阿斯玛鲁矿山４楼 | 31804 | yes | yes | no |
| 阿斯玛鲁矿山５楼 | 31805 | yes | no | `genout/wpm_31805_22_4` |
| 阿斯玛鲁矿山６楼 | 31806 | yes | yes | `genout/wpm_31805_22_4` |
| 吉鲁采石场１楼 | 31901 | yes | yes | no |
| 采石场事务所 | 31902 | yes | no | no |
| 吉鲁采石场２楼 | 31903 | yes | yes | `genout/wpm_31903_39_4` |
| 吉鲁采石场３楼 | 31904 | yes | yes | `genout/wpm_31903_39_4`, `genout/wpm_31910_10_11`, `genout/wpm_31910_13_12`, `genout/wpm_31910_13_5` |
| 吉鲁采石场４楼 | 31905 | yes | yes | `genout/wpm_31910_12_9`, `genout/wpm_31910_14_8`, `genout/wpm_31910_5_8` |
| 吉鲁采石场５楼 | 31906 | yes | yes | `genout/wpm_31910_10_8`, `genout/wpm_31910_6_11`, `genout/wpm_31910_6_6` |
| 吉鲁采石场６楼 | 31907 | yes | yes | `genout/wpm_31910_11_6`, `genout/wpm_31910_15_5`, `genout/wpm_31910_9_5` |
| 吉鲁采石场７楼 | 31908 | yes | yes | no |
| 吉鲁采石场８楼 | 31909 | yes | no | `giiru/event/event30_7` |
| 真知之间 | 31910 | yes | no | `genout/wpm_31910_10_11`, `genout/wpm_31910_10_8`, `genout/wpm_31910_11_6`, `genout/wpm_31910_12_9`, `genout/wpm_31910_13_12`, `genout/wpm_31910_13_5`, `genout/wpm_31910_14_8`, `genout/wpm_31910_15_5`, `genout/wpm_31910_5_8`, `genout/wpm_31910_6_11`, `genout/wpm_31910_6_6`, `genout/wpm_31910_8_9`, `genout/wpm_31910_9_5`, `giiru/event/event30_7` |
| 精灵之间 | 31911 | yes | no | `genout/wpm_31910_8_9` |

Deferred original map names (not imported):

| Map | ID | Reason |
| --- | --- | --- |
| 长老房间 | 5107 | no reachable original entrance |
| 达那密道 | 9355 | no reachable original entrance |
| 蛇王巢穴 | 9356 | no reachable original entrance |
| 达那密道 | 9357 | no reachable original entrance |
| 火山裂缝通道 | 30017 | trailing bytes; no incoming entrance |
| 水晶洞窟 | 30022 | 8.0 graphics recoverable; no incoming entrance |
| 水晶洞窟 | 30023 | 8.0 graphics recoverable; no incoming entrance |
| 水晶洞窟 | 30024 | 8.0 graphics recoverable; no incoming entrance |
| 水晶洞窟 | 30025 | 8.0 graphics recoverable; no incoming entrance |
| 水晶洞窟核心 | 30026 | 8.0 graphics recoverable; no incoming entrance |
| 地下１楼 | 30901 | no reachable original entrance |
| 地下２楼 | 30902 | no reachable original entrance |
| 地下３楼 | 30903 | no reachable original entrance |
| 地下２楼 | 30904 | no reachable original entrance |
| 地下１楼 | 30905 | no reachable original entrance |
| 没落的矿坑１楼 | 31201 | cross-floor entrance conflict |
| 没落的矿坑２楼 | 31202 | cross-floor entrance conflict |
| 没落的矿坑３楼 | 31203 | cross-floor entrance conflict |
| 没落的矿坑４楼 | 31204 | cross-floor entrance conflict |
| 没落的矿坑５楼 | 31205 | cross-floor entrance conflict |
| 方位的祠 | 31604 | arrival component lacks verified return |
| 方位的祠 | 31605 | arrival component lacks verified return |
| 方位的祠 | 31606 | arrival component lacks verified return |
| 方位的祠 | 31607 | arrival component lacks verified return |
| 方位的祠 | 31608 | arrival component lacks verified return |
| 方位的祠 | 31609 | arrival component lacks verified return |
| 方位的祠 | 31610 | arrival component lacks verified return |

## Seimu

Adds eight connected scenery maps (404 total after this region), reached through
original doors from developer-only island 400 and the Giru underwater passages.
Island 400 keeps its training kind, original encounters and `dev_only` flag.
No original services, dream-cave quest, boss or event progression is restored.
The three exact `genout/wpm_40_1_8`, `genout/wpm_40_13_1`, and
`genout/wpm_40_12_18` gates retain their original underwater destinations. Their source scripts have
empty `FREE:` and `MONEY:300` (paid NPC passage, with party restrictions);
this implementation uses the existing reusable profile `travel_pass` instead
of restoring the original 300-stone fee dialogue. All six directions between
40 and 31301/31401/31501 require that permit, including the originally ordinary
return doors. This deliberate restriction prevents bypassing the 10202 gate
from Sainas, Jyaruga, Giru or developer-only Seimu. No `400/sb_muge1.arg` or `sb_muge2.arg`
event is whitelisted: those boss scripts incorrectly send floor42 to floor41.
Ordinary compiled dream-cave teleport NPCs retain their original destinations.

The region has 141 original portal records touching the eight added maps: 135
active and six disabled. Two conflicting destinations at 42(45,59) remain
closed, and four additional floor42 doors enter components without a restored
return path. All eight map spawns and reachable active arrivals can return to
an existing island. Hospital6005 has only village6000(44,67) as an incoming
door; village(43,67) is an original return destination, not an invented entry.
Room6012 has no door in the full recursive NPC/mapwarp scan and stays deferred.

Map40's original 20×20 LS2MAP is 1645 bytes, including one trailing zero byte.
Original `server_readmap` reads exactly two 400-short layers and ignores it.
The importer accepts this exception only for ID40, these dimensions and length,
that zero byte, and SHA256
`75eef0bbf69f257b7f3705a1fef98242a4cf2d375cb8838f87a5411297fd9727`.
Unknown trailing data, including another file with the same header, is rejected.
The existing 8.0 logical15401 fallback for island400 remains namespaced; all
added maps have zero missing graphics and a dedicated on-demand web map pack.

| Map | ID | Encounter area | Random encounters | NPC gate directly opened |
| --- | --- | --- | --- | --- |
| 奇努伊关卡 | 40 | yes | no | no; all three sea routes require profile travel_pass in both directions |
| 梦幻的洞窟 | 41 | yes | yes | no |
| 梦幻的洞窟 | 42 | yes | yes | no; conflicting/non-returning internal doors closed |
| 沙姆岛 (existing developer training map) | 400 | yes | yes | no |
| 奇努伊村 | 6000 | yes | no | no |
| 奇努伊的肉店 | 6004 | no | no | no |
| 奇努伊的医院 | 6005 | no | no | no |
| 奇努伊的村长家 | 6006 | no | no | no |
| 奇努伊的便利商店 | 6009 | no | no | no |
| 奇努伊室内 (deferred; no original doors) | 6012 | no | no | no |


## Jyaruga service interiors and Ruri floor15 (2026-09-30)

Review: `tools/world_regions/jyaruga_interiors.json`; 31 candidates, **4 imported,
27 deferred**. This restores scenery and original walking doors only. Source
collision and warp cells/directions remain unchanged. No NPC service, quiz or
hundred-person dojo battle implementation is included.

The exact 102 gate-script allowlist has been checked: `200/sb_dbt.arg`,
`genout/wpm_3020_18_12`, and `doujyou/jyajyadou001.arg` through `100.arg`.
Only `200/sb_dbt.arg` is active in the resulting manifest: original 21014
(14,14) → 21015 (9,17), with the NPC/battle condition bypassed as a developer
scenery convenience. The landing is also the original return portal; runtime
arrival suppression keeps the player on floor15 until leaving (9,16) and
walking back onto (9,17).

The 3020 fee NPC's original cell (18,12) lies behind the counter in a separate
walking component. The entrance (4,12) and infirmary return (12,9) are in the
main component; source collision blocks column17. Thus the fee bypass
(original LV*5) cannot be reached by walking, and the component finalizer
removes 3021, 3022 and 3008. The reviewed scripts remain in the allowlist for
source auditing; this does **not** mean their rooms or gate chain are open.
Future original NPC interaction is required, rather than moving the door or
inventing links. All 100 original fight-result gates keep their source cells:
`x=400-44*floor((n-1)/10), y=124-12*((n-1)%10)`; destinations come directly from
the corresponding arg, with gate100 → 3008 (20,20). Original side doors
lead to 3022 (1,7); both medical/master rooms return to 3020 (12,9).

Ordinary doors retained: 200 (328,660/661) ↔ 201 (6,19/20),
3000 (112,80/81) → 3020 (4,12), and 4000 (82,107) ↔ 4020 (4,12).
The latter comes from `quiz.create`; quiz destination851 stays excluded.
No reverse gates are synthesized.

“Original encounter area” below records the source catalog entry; “Active
encounters” additionally requires a positive probability and nonempty groups.
The newly opened interiors and floor15 have no active ordinary encounters.

| Map ID | Original name | Original encounter area | Active encounters | Result / relaxed door or deferred reason |
| --- | --- | --- | --- | --- |
| 201 | 卡鲁它那牧场事务所 | yes | no | Open; original ordinary doors |
| 3008 | 师傅的房间 | no | no | Deferred; fee NPC behind counter, entry component unreachable; battles not restored |
| 3020 | 加加的道场柜台 | no | no | Open; original ordinary doors |
| 3021 | 百人联手道场 | no | no | Deferred; fee NPC behind counter, entry component unreachable; battles not restored |
| 3022 | 加加的道场医务室 | no | no | Deferred; fee NPC behind counter, entry component unreachable; battles not restored |
| 3208 | 多多的道场 | no | no | Deferred; no original incoming/outgoing door |
| 3308 | 乌鲁力的道场 | no | no | Deferred; no original incoming/outgoing door |
| 4008 | 卡鲁它那的道场 | no | no | Deferred; no original incoming/outgoing door |
| 4020 | 卡鲁他那道场柜台 | no | no | Open; original ordinary doors |
| 20001 | 拉多拉山岭洞窟１楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20002 | 拉多拉山岭洞窟２楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20003 | 拉多拉山岭洞窟３楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20004 | 拉多拉山岭洞窟４楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20005 | 拉多拉山岭洞窟５楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20006 | 拉多拉山岭洞窟６楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20007 | 拉多拉山岭洞窟７楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20008 | 拉多拉山岭洞窟８楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20009 | 拉多拉山岭洞窟９楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20010 | 拉多拉山岭洞窟１０楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20011 | 拉多拉山岭洞窟１０楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20012 | 拉多拉山岭洞窟１０楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 20013 | 拉多拉山岭洞窟１０楼 | no | no | Deferred; internal group stairs only, no outside entrance |
| 21015 | 琉璃的洞窟１５楼 | yes | no | Open; original sb_dbt NPC/battle gate bypass (developer convenience) |
| 21103 | 拉多拉洞窟山顶 | no | no | Deferred; no original walking entrance |
| 21106 | 拉多拉洞窟山顶 | no | no | Deferred; no original walking entrance |
| 21108 | 碧青的洞窟地下８楼 | no | no | Deferred; no original walking entrance |
| 21109 | 拉多拉洞窟山顶 | no | no | Deferred; no original walking entrance |
| 21110 | 碧青的洞窟地下１０楼 | no | no | Deferred; no original walking entrance |
| 21111 | 碧青的洞窟地下１１楼 | no | no | Deferred; no original walking entrance |
| 21112 | 拉多拉洞窟山顶 | no | no | Deferred; no original walking entrance |
| 21113 | 碧青的洞窟地下１３楼 | no | no | Deferred; no original walking entrance |

## Rebuild / verify

After each region commit, main must re-run the world importer,
`tools/plan_web_packs.py`, `tools/build_exit_names.py`, and the headless editor
import. `tools/verify_world_regions.py --region <region>` checks zero missing
graphics, original encounters, dedicated web map packs and walking-component
travel from/return to an existing island. It also checks every reachable arrival
component for a return path. The headless suites do not verify rendered pixels.

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/plan_web_packs.py
python3 tools/build_exit_names.py
./scripts/run.sh --headless --editor --import --quit
.tools/asset-venv/bin/python tools/verify_world_regions.py --region sainasu
.tools/asset-venv/bin/python tools/verify_world_regions.py --region giiru
.tools/asset-venv/bin/python tools/verify_world_regions.py --region seimu
.tools/asset-venv/bin/python tools/verify_world_regions.py --region jyaruga_interiors
```
