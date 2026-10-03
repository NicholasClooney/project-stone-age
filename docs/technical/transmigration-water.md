# Water46 source and validation review

Scope: second-stage water46 only. No rebirth settlement. Original Samgir=1 SP, villager conversation=0.5 SP; incremental estimate 0.75–1.5 SP, shared foundation excluded. Source revision `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.

## Source behavior

The exact source oracle contains15 NPCs:13 water-exclusive entries and2 independently active adult-gated stone entrances. Disabling46 removes exactly the13 exclusive entries while preserving both original adult entrances.

- Acceptance: level65+, END4, ANY of END39/40/42. Preserve three source branches in order.
- Synthesis: preserve the approved missing-crystal OR exactly. Bare DelItem consumes every copy of2767/2768. The original sage door still checks BOTH materials, NOW46 and END4.
- Reward: level65+, NOW46,2769; consumes all2769, grants2770, charm+1 and END46.
- Small/large box:36 slots each,24 distinct equipment IDs; 12 original choices occur twice. No NOW/END gate and no invented once-only limit; every exchange consumes all2766 and gives one roll.
- Enemy1324 drops2767 at800/1000. Enemies1334–1336 drop1249 at50/1000 AND2766 at20/1000;1347–1349 drop1238 at100/1000 AND2766 at20/1000. All13 slots selected, not just the quest shell.
- Original raw materials1238/1249 retain use effects as inactive metadata until a separately approved runtime exists. No original-item selling is added.
- Two original ten-enemy guards use current AI; original tactics and skill metadata remain in the foundation combat audit.
- The32 water maps21201–21215,21301–21315,31301/31302 are promoted; seven already-original stone-island maps30301–30307 are explicitly retained after replacing both convenience entrances. The return entry at200(316,711) retains END46 and shell conditions. First-time access to the sage is through21215→21315, not that post-completion shortcut.
- Lake access has two legitimate original entries: the paid40(13,1) script (300 stone) and the ordinary Ford5000(46,18)→31301(10,10) portal. Both can reach31301(9,51)→31302(52,11); the paid route is not mandatory. Evidence: `gmsv/data/map/mapwarp.txt:2739–2743` and `gmsv/data/npc/genout/dungeon03.create:61–103` (entry blocks start61/70, inner passage88/97). The imported graph retains these ordinary bidirectional portals without added quest, fee or travel-pass gates.
- Duplicate portal21215(26,11) uses first original source destination21315(52,59), mapwarp2397/create2215; both source orders agree. Alternative26,10 remains source53,59.

## Every selected item

The manifest pins itemset SHA `c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d`. Fields below are literal source metadata; ordinary equipment support is owned by the shared equipment implementation, not implied by importing an item. Magic/resistances remain inactive.

| ID | Name | Line | Icon | Type | Level | ATK | DEF | SPD | Charm | Durability | Magic | Pile24/25 |
|---|---|---:|---:|---:|---:|---|---|---|---|---|---|---|
| 74 | 莱伊萨Lv4斧头 | 75 | 20004 | 1 | 40 | 47/47 | -15/-15 | -15/-15 | 0/0 | 300000 | 178 | ['', ''] |
| 75 | 特洛金Lv4斧头 | 76 | 20004 | 1 | 40 | 47/47 | -15/-15 | -15/-15 | 0/0 | 300000 | 188 | ['', ''] |
| 77 | 特洛金Lv4斧头 | 78 | 20004 | 1 | 40 | 47/47 | -15/-15 | -15/-15 | 0/0 | 300000 | 188 | ['', ''] |
| 78 | 特洛金Lv4斧头 | 79 | 20004 | 1 | 40 | 47/47 | -15/-15 | -15/-15 | 0/0 | 300000 | 188 | ['', ''] |
| 184 | 莱伊卡Lv5棍棒 | 185 | 20146 | 2 | 50 | 35/35 | 0/0 | 0/0 | 0/0 | 300000 | 174 | ['', ''] |
| 185 | 特洛西Lv5棍棒 | 186 | 20146 | 2 | 50 | 35/35 | 0/0 | 0/0 | 0/0 | 300000 | 184 | ['', ''] |
| 192 | 威金娜斯Lv5棍棒 | 193 | 20148 | 2 | 60 | 39/39 | 0/0 | 0/0 | 0/0 | 300000 | 159 | ['', ''] |
| 193 | 贝所金Lv5棍棒 | 194 | 20148 | 2 | 60 | 39/39 | 0/0 | 0/0 | 0/0 | 300000 | 169 | ['', ''] |
| 282 | 威金尼尔Lv5枪 | 283 | 20436 | 3 | 50 | 43/43 | 0/0 | -9/-9 | 5/5 | 300000 | 154 | ['', ''] |
| 283 | 迪所斯Lv5枪 | 284 | 20436 | 3 | 50 | 43/43 | 0/0 | -9/-9 | 5/5 | 300000 | 164 | ['', ''] |
| 287 | 特洛西Lv5枪 | 288 | 20436 | 3 | 50 | 43/43 | 0/0 | -9/-9 | 5/5 | 300000 | 184 | ['', ''] |
| 288 | 特洛西Lv5枪 | 289 | 20436 | 3 | 50 | 43/43 | 0/0 | -9/-9 | 5/5 | 300000 | 184 | ['', ''] |
| 378 | 特洛金Lv4爪 | 379 | 20223 | 0 | 40 | 23/23 | 0/0 | 0/0 | 0/0 | 1200000 | 188 | ['', ''] |
| 379 | 特洛金Lv4爪 | 380 | 20223 | 0 | 40 | 23/23 | 0/0 | 0/0 | 0/0 | 1200000 | 188 | ['', ''] |
| 383 | 迪所斯Lv5爪 | 384 | 20219 | 0 | 50 | 26/26 | 0/0 | 0/0 | 0/0 | 1200000 | 164 | ['', ''] |
| 384 | 莱伊卡Lv5爪 | 385 | 20219 | 0 | 50 | 26/26 | 0/0 | 0/0 | 0/0 | 1200000 | 174 | ['', ''] |
| 477 | 特洛金Lv4弓箭 | 478 | 20335 | 4 | 45 | 16/16 | -16/-16 | 0/0 | 0/0 | 1200000 | 188 | ['', ''] |
| 478 | 特洛金Lv4弓箭 | 479 | 20335 | 4 | 45 | 16/16 | -16/-16 | 0/0 | 0/0 | 1200000 | 188 | ['', ''] |
| 485 | 特洛西Lv5弓箭 | 486 | 20344 | 4 | 50 | 18/18 | -18/-18 | 0/0 | 0/0 | 1200000 | 184 | ['', ''] |
| 486 | 特洛西Lv5弓箭 | 487 | 20344 | 4 | 50 | 18/18 | -18/-18 | 0/0 | 0/0 | 1200000 | 184 | ['', ''] |
| 578 | 特洛金Lv4回旋标 | 579 | 20542 | 17 | 45 | 20/20 | 0/0 | 0/0 | 3/3 | 1200000 | 188 | ['', ''] |
| 579 | 特洛金Lv4回旋标 | 580 | 20542 | 17 | 45 | 20/20 | 0/0 | 0/0 | 3/3 | 1200000 | 188 | ['', ''] |
| 584 | 莱伊卡Lv5回旋标 | 585 | 20523 | 17 | 50 | 22/22 | 0/0 | 0/0 | 3/3 | 1200000 | 174 | ['', ''] |
| 585 | 特洛西Lv5回旋标 | 586 | 20523 | 17 | 50 | 22/22 | 0/0 | 0/0 | 3/3 | 1200000 | 184 | ['', ''] |
| 676 | 特洛金Lv4投掷斧头 | 677 | 20533 | 18 | 40 | 31/31 | 0/0 | 0/0 | 0/0 | 300000 | 188 | ['', ''] |
| 677 | 特洛金Lv4投掷斧头 | 678 | 20533 | 18 | 40 | 31/31 | 0/0 | 0/0 | 0/0 | 300000 | 188 | ['', ''] |
| 681 | 贝诺美斯Lv5投掷斧头 | 682 | 20506 | 18 | 50 | 35/35 | 0/0 | 0/0 | 0/0 | 300000 | 134 | ['', ''] |
| 682 | 威金尼尔Lv5投掷斧头 | 683 | 20506 | 18 | 50 | 35/35 | 0/0 | 0/0 | 0/0 | 300000 | 154 | ['', ''] |
| 773 | 贝所金Lv4石 | 774 | 20503 | 19 | 40 | 23/23 | -4/-4 | 0/0 | 0/0 | 300000 | 168 | ['', ''] |
| 774 | 莱伊萨Lv4石 | 775 | 20503 | 19 | 40 | 23/23 | -4/-4 | 0/0 | 0/0 | 300000 | 178 | ['', ''] |
| 782 | 威金尼尔Lv5石 | 783 | 20526 | 19 | 50 | 26/26 | -5/-5 | 0/0 | 0/0 | 300000 | 154 | ['', ''] |
| 783 | 迪所斯Lv5石 | 784 | 20526 | 19 | 50 | 26/26 | -5/-5 | 0/0 | 0/0 | 300000 | 164 | ['', ''] |
| 874 | 渥鲁菲Lv1兜8 | 875 | 21515 | 6 | 40 | 0/0 | 14/14 | -4/-4 | 0/0 | 300000 | 110 | ['', ''] |
| 875 | 米鲁菲Lv1兜8 | 876 | 21515 | 6 | 40 | 0/0 | 14/14 | -4/-4 | 0/0 | 300000 | 120 | ['', ''] |
| 877 | 米鲁菲Lv1兜8 | 878 | 21515 | 6 | 40 | 0/0 | 14/14 | -4/-4 | 0/0 | 300000 | 120 | ['', ''] |
| 878 | 米鲁菲Lv1兜8 | 879 | 21515 | 6 | 40 | 0/0 | 14/14 | -4/-4 | 0/0 | 300000 | 120 | ['', ''] |
| 975 | 米鲁菲Lv2帽子8 | 976 | 21506 | 6 | 40 | 0/0 | 7/7 | 0/0 | 0/0 | 300000 | 121 | ['', ''] |
| 976 | 米鲁菲Lv2帽子8 | 977 | 21506 | 6 | 40 | 0/0 | 7/7 | 0/0 | 0/0 | 300000 | 121 | ['', ''] |
| 982 | 爱鲁菲Lv2帽子9 | 983 | 21535 | 6 | 50 | 0/0 | 8/8 | 0/0 | 0/0 | 300000 | 91 | ['', ''] |
| 983 | 所鲁菲Lv2帽子9 | 984 | 21535 | 6 | 50 | 0/0 | 8/8 | 0/0 | 0/0 | 300000 | 101 | ['', ''] |
| 1064 | 哈鲁Lv2铠7 | 1065 | 21018 | 7 | 35 | 0/0 | 26/26 | -7/-7 | 0/0 | 300000 | 1 | ['', ''] |
| 1065 | 芙雷雅Lv2铠7 | 1066 | 21018 | 7 | 35 | 0/0 | 25/25 | -7/-7 | 0/0 | 300000 | 11 | ['', ''] |
| 1069 | 提欧Lv3铠7 | 1070 | 21020 | 7 | 35 | 0/0 | 26/26 | -7/-7 | 0/0 | 300000 | 22 | ['', ''] |
| 1070 | 厉害的铠 | 1071 | 21059 | 7 | 40 | 0/0 | 32/32 | -8/-8 | 0/0 | 300000 |  | ['', ''] |
| 1168 | 芙雷雅Lv3服7 | 1169 | 21012 | 7 | 35 | 0/0 | 16/16 | 0/0 | 0/0 | 300000 | 12 | ['', ''] |
| 1169 | 提欧Lv3服7 | 1170 | 21012 | 7 | 35 | 0/0 | 16/16 | 0/0 | 0/0 | 300000 | 22 | ['', ''] |
| 1172 | 芙雷雅Lv1服8 | 1173 | 21028 | 7 | 40 | 0/0 | 17/17 | 0/0 | 0/0 | 300000 | 10 | ['', ''] |
| 1173 | 提欧Lv1服8 | 1174 | 21028 | 7 | 40 | 0/0 | 17/17 | 0/0 | 0/0 | 300000 | 20 | ['', ''] |
| 1238 | 大块肉 | 1233 | 24044 | 20 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | / |  | ['', '1'] |
| 1249 | 治疗石化肉 | 1244 | 24038 | 20 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | / |  | ['', '1'] |
| 2766 | 水苍之贝 [水] | 2277 | 24133 | 15 | 65 | 0/0 | 0/0 | 0/0 | 3/3 | / |  | ['', ''] |
| 2767 | 深蓝色石头 | 2278 | 24198 | 16 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | / |  | ['', ''] |
| 2768 | 群青的水 | 2279 | 23012 | 16 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | / |  | ['', ''] |
| 2769 | 碧青水晶 | 2280 | 14648 | 16 | 0 | 0/0 | 0/0 | 0/0 | 0/0 | / |  | ['', ''] |
| 2770 | 水的戒指[水] | 2281 | 22124 | 11 | 0 | 0/0 | 0/0 | 0/0 | 3/3 | 300000 |  | ['', ''] |

## Runtime boundaries and directed evidence

The descriptor enables exactly46; thirteen actual create-bound NPCs and55 item IDs are source-reviewed. The two ignored unkeyed source headings are explicitly pinned by physical line/text. Do not import a similarly named unbound script. Box capacity uses the original net bag count after full bare-ID consumption; full15 slots may still exchange when the shells free space. A worn shell alone does not satisfy `ITEM=2766`; when another shell is in the bag, bare `DelItem:2766` also removes the worn copy and clears its equipment UID slot.

The independent helper owns both final navigation modes and rechecks current server steps. Cave/material NPCs require server-owned legitimate arrival, the currently selected original branch, the current map and connected component with original doors/NPC cells excluded, and actual talk range. Both navigation modes return only the existing authority position. A stale cached step or raw NPC ID cannot convert a project jump into route authorization. The stone encounter step is tied to original area570/group718/enemy1324 on30305; optional shell hunting is area581/group723 on21209. These do not provide an inter-map shortcut. The area target must resolve to the same imported source area, and anonymous encounter requests match the server step map/cell. Optional post-completion shell exchanges retain original source gate access.

The shared transaction-level **legitimate arrival** API and water policy (`f3026a2`) guard project teleport routes. This chain uses the shared server-owned memory and does not invent a competing receipt. The protected transactions are hekisei01 branch0 (END46/ring/charm), hekisei03 branch1 (crystal), hekisei04 branch1 (water), hekisei05/06 branch0 (boxes). Proof boundaries are both original water guards, the real21308 material door, and either original lake entry (paid40→31301 OR ordinary5000→31301), followed by the ordinary31301→31302 path. The END46+shell back entrance is also a legitimate re-entry but cannot prove first completion. The original transaction entry and final commit independently recheck this authority; helper geometry alone is not authorization. The sage needs the `water_material` mark from a successfully saved original material-door Warp, which expires outside that room. Reload and project movement do not restore it.

The single complete `transmigration_water_ui_test.gd` E2E, reusing `tests/support/water_walking_ui.gd`, starts at the adult entrance with explicitly seeded level/NOW46/materials and combat stats, then uses production adjacent walking, actual portals, both real10-enemy victories, the21215→21315 passage, reverse floors to21308 and the real material door before synthesis, then follows the original exit and reverse portals to return the crystal to the goddess. It is a route/transaction proof, not a claim that materials were naturally farmed in that same run. `transmigration_water_drops_test.gd` separately exercises actual1324/shell drops, all13 slots, save failure and same-roll retry. `transmigration_water_test.gd` uses explicit level/event/material/combat fixtures, then the shared production command route driver for protected NPC access, exhaustive conditions, UID, save, LAN and navigation adversarial cases. The water-specific driver does not write arrival receipts. Its public approach fixture is followed by actual per-cell report_position, original gate commits and real guard battles. The UI E2E instead uses asynchronous real remote walking and waits for each position acknowledgement, then performs the actual phone clicks; it does not queue a synchronous route into an attached WebSocket. Material acquisition/combat strength remain test fixtures. There is no separately registered duplicate full walking suite. The transaction suite reuses one character’s actual route for its same-room transactions rather than rebuilding the entire chain for each assertion. New arrival tests independently check both real lake roots and capture/project movement denial. These suites exercise the combined production hooks and water policy. Preexisting level/events/materials are explicit test state, never fabricated arrival marks.

## Remaining ordinary material-route boundary

Final NPC arrival protection does not by itself establish a legitimate route for ordinary quest-material drops. Enemy1324 drops2767 on30305. Both source entrances are restored:300(247,222)→30301(23,37) and300(182,162)→30307(10,6), each with its own original65+END4 condition and no fee. Source `mapwarp.txt:1975–1994` links30301–30307, including three30305/30306 connections. Neither root is a bypass. The installed shared arrival policy883bf9b owns this complete scope and both saved script roots; ordinary2767/drop policy remains a separately coordinated decision. This chain does not invent arrival marks or suppress companion loot1238/1249. Full drop-slot fidelity alone is not proof of route authorization.

## Exact asset import chain

In an `--import` pool clone, with the existing verified base assets inherited from main, this branch ran:

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/palette_images.py
python3 tools/split_manifests.py
./scripts/run.sh --headless --editor --import --quit
python3 tools/plan_web_packs.py
.tools/asset-venv/bin/python tools/test_transmigration_water_assets.py
```

At the water-only activation snapshot:450 maps/1598 portals/4751 source images,257 quest NPCs/188 item definitions. Other simultaneously merged chains change the combined totals. All55 item icons are pixel-equal to their original archive bitmap and owned by the core web pack. All32 promoted water maps and seven retained stone-island maps have pack dependencies;32021 remains dev_only with no spirit king. Imported assets, web-pack outputs and screenshots are not committed. No encounter-table reimport is needed: existing original enemy/area data contains these slots, and the quest catalog activates only this reviewed enemy whitelist.
