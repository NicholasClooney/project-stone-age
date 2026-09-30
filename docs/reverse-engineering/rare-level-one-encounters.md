# Rare Lv.1 encounters in high-level areas

The original gives several strong pets a rare **Lv.1** encounter inside a high-level area, next to the same pet at its normal level. This project reuses that pattern so players can hunt Lv.1 versions of classic pets that have no Lv.1 wild spot (自动抓宠, 找宠, 后台搜宠, 本机极速模式, 属性条件, Lv.120 prediction). Every addition is marked in the data and in 宠物大全. None of them is an original row.

## Evidence in the original tables

Pinned `references/chenmingbiao-stone-age/gmsv/data` (`encount.txt`, `group.txt`, `enemy.txt`). The weight share is the group's weight out of the area's ordinary (not item-gated) weight total, which is what `encounter_catalog.gd roll()` picks groups by. "Per battle" is how often an encounter in that area contains the Lv.1 pet (troop size and caps simulated like `roll()`).

| Area | Lv.1 group | Share | Per battle | Makeup |
|---|---|---|---|---|
| 漆黑的洞窟 地下18楼 (32018, area 628) | 751: 1397 布林帖斯 Lv1 (max 1) + 1398 布林帖斯 Lv93–95, 1:1 | 1/101 (0.99%) | 0.83% | **reference** |
| 漆黑的洞窟 地下9楼 (32009, 619) | 738: 1386 阿伊萨 Lv1 + 1387 阿伊萨 Lv88–90, 1:1 | 1/101 | 0.82% | same shape |
| 漆黑的洞窟 地下19楼 (32019, 629) | 749: 1395 拉可拉斯 Lv1 + 1396 拉可拉斯 Lv93–95, 10:10 | 1/101 | 0.82% | same shape |
| 五十年前波拉岛 龙穴 (500, 652) | 775: 1451 邦恩多斯 Lv1 + 1447 邦恩多斯 Lv95–105, 2:40 | 2/52 (3.8%) | 1.1% | dragon lair |
| 加鲁卡 (200, 150 / 147) | 271 / 275: 贝鲁卡 / 贝鲁伊卡 Lv1 alone | 1/91 | 1.1% | Lv14–20 tiger fields |
| 吉鲁岛 (300, 308) | 435: 格鲁西斯 Lv1 alone | 1/81 | 1.2% | Lv40–42 area |
| 沙姆岛 (400, 383) | 528: 布拉奇多斯 Lv1 alone | 1/53 | 1.9% | Lv36–45 area |

Two more things the original does:

- The floors that hold a Lv.1 group have their weights **scaled up** so that weight 1 is about 1%: 地下9/18/19楼 use 20/25/40 where their neighbours 地下6–8, 10, 16 and 17楼 use 1 or 3 and add up to 4–7.
- The enemy table has **unused Lv.1 pet rows** (level 1–1, capturable, in no group) for many pets: 巴朵兰恩 352, 左迪洛斯 351, 奥卡洛斯 350, 帖拉所伊朵 353, 金格萨贝鲁 310, 帖拉格恩 338, 洛卡伦恩 339, 加宝格恩 340, 朵拉比斯 341, 布洛多斯 330, 布林帖斯 331, 斯天多斯 333, 邦恩多斯 483, 黑乌力 475, 邦达霍恩 484, 年兽 1794–1797, 普鲁夏 1609, 佩露夏 1610, 萨格鲁 1611, 玛斯贝卡 1612, the 水5火5 巴朵兰恩 2572 and more. Some rows are dungeon Lv.1 entries on maps we have not imported: 1037 奥卡洛斯 (31806 阿斯玛鲁矿山), 1368 加宝格恩 (30702), 1557 布洛多斯 (5507), 1450 斯天多斯 (英雄岛龙穴, the twin of 1451).

## The rule used here

`client/data/rare-encounters.json` holds the additions. `tools/import_encounters.py` (`add_rare_encounters`) merges it into `client/assets/legacy/encounters/catalog.json`. That is the only place additions enter; the server rolls, the fast hunt helper (it gets the area's groups from `fast_hunt.gd _input`), 宠物大全, `tools/build_training_spots.py`, `tools/build_level_one_spots.py` (地图导航's Lv.1 list) and `tools/build_species_potential.py` all read the merged catalog.

- Each addition is a new group like group 751: **{the Lv.1 row, weight 1; a companion, weight 1}** with area weight **1**. The companion is a high-level enemy already in the area's original groups: the same pet where the area has it, else its closest kin there. The 年兽 have none (they appear alone). Group ids are 91001+, and each group carries `rare: {origin, template_id, enemy_id, reason}`.
- The Lv.1 row is the pet's own original Lv.1 row: a dungeon Lv.1 entry where one exists, else the unused Lv.1 row. When the only Lv.1 row is not capturable (pet_flag 0), or there is none, a **clone** gets id 90001+, level 1–1, capturable, at most one per troop and `clone_of` the source row. Everything else stays as in the source row. Capture difficulty is always the template's own `capture_resistance`.
- Areas whose ordinary weights add up to much less than 100 get **scaled** by a whole factor (`areas` in the file, `weight_scale` on the area), like the original's own Lv.1 floors. That changes no ratio between original groups. Resulting shares are 0.79%–1.28% per addition (reference 0.99%). A test keeps every share between 0.5% and 1.5%.
- On the 地图导航 map these spots are labelled and outlined in violet instead of the Lv.1 green (`PetEncyclopedia.level_one_areas` returns them as separate `added` entries); the legend explains the colour.
- `origin` is `original_area` (**补充**) when the pet has an original wild row in that area at a higher level, and `added` (**原版无野外，非原版**) when it has no original wild area on an imported map. Original Lv.1 rows (布林帖斯 in 地下18楼, 邦恩多斯 in the 龙穴, 布拉奇多斯 on 沙姆岛, the tigers) are unchanged and unmarked.

## Spots

Map 500 五十年前波拉岛 is reached with 地图导航 or 宠物大全's 瞬移去抓. "Per battle" means per encounter in that area.

| Pet (template) | Map · area | Lv | Weight (share) | Per battle | Lv.1 row | Companion | Origin | Why here |
|---|---|---|---|---|---|---|---|---|
| 巴朵兰恩 红暴 (303) | 五十年前波拉岛 · 639 (whole island) | 1 | 1/115 (0.87%) | 0.71% | 352 | 1473 红暴 Lv90–95 | 补充 | original Lv90–95 red rex area |
| 奥卡洛斯 绿暴 (301) | 五十年前波拉岛 · 652 (龙穴) | 1 | 1/107 (0.93%) | 0.79% | 1037 | 1474 绿暴 Lv90–95 | 补充 | original Lv90–95 green rex area |
| 斯天多斯 绿雷龙 (254) | 五十年前波拉岛 · 652 | 1 | 1/107 (0.93%) | 0.73% | 1450 | 1471 | 补充 | original Lv90–95; 1450 is 1451's twin |
| 布洛多斯 (251) | 五十年前波拉岛 · 638 | 1 | 1/94 (1.06%) | 0.83% | 1557 | 1465 | 补充 | original Lv80–90 thunder dragon area |
| 加宝格恩 (273) | 漆黑的洞窟 地下9楼 · 619 | 1 | 1/102 (0.98%) | 0.82% | 1368 | 1388 | 补充 | original Lv88–90 |
| 卡特利奴 卡虎 (524) | 加鲁卡 · 143 | 1 | 1/93 (1.08%) | 0.84% | clone of 539 | 415 贝鲁卡 | 补充 | original quest encounter (走失的红虎, item-gated Lv15) is here |
| 左迪洛斯 蓝暴 (302) | 五十年前波拉岛 · 639 | 1 | 1/115 (0.87%) | 0.71% | 351 | 1473 | 非原版 | dragons live on this island |
| 斑尼迪克 金暴 (812) | 五十年前波拉岛 · 639 | 1 | 1/115 | 0.70% | clone of 1645 | 1473 | 非原版 | rex island |
| 邦达霍恩 黑羊 (315) | 五十年前波拉岛 · 652 | 1 | 1/107 | 0.84% | 484 | 1463 卡伊霍恩 | 非原版 | its family (卡伊霍恩, 拉伊霍恩) lives only here |
| 帖拉格恩 (271) | 漆黑的洞窟 地下6楼 · 616 | 1 | 1/99 (1.01%) | 0.89% | 338 | 1388 加宝格恩 | 非原版 | original wild only on 30701–30703 (not imported); its kin 加宝格恩 lives on 地下6–10楼 |
| 洛卡伦恩 (272) | 地下7楼 · 617 | 1 | 1/103 (0.97%) | 0.86% | 339 | 1388 | 非原版 | flying dragon floors |
| 朵拉比斯 金飞 (274) | 地下8楼 · 618 | 1 | 1/99 (1.01%) | 0.89% | 341 | 1388 | 非原版 | flying dragon floors |
| 艾迪希洛 机豹 (968) | 地下19楼 · 629 | 1 | 1/102 (0.98%) | 0.82% | clone of 1946 | 1396 拉可拉斯 | 非原版 | the machine pets go with 机暴's cave; this floor already has an original Lv.1 |
| 帖拉所伊朵 机暴 (304) | 地下20楼 · 630 | 1 | 1/121 (0.83%) | 0.73% | 353 | 1398 布林帖斯 | 非原版 | the cave's guardian (bosses 1404 黑色帖拉所伊朵, 1942 钻石帖拉所依朵); deepest floor |
| 金格萨贝鲁 金虎 (194) | 加鲁卡 · 152 | 1 | 1/78 (1.28%) | 1.13% | 310 | 417 贝鲁卡 Lv18–20 | 非原版 | the tigers' home outside 琉璃洞窟, highest tiger field |
| 普鲁夏 蓝虎 (776) | 加鲁卡 · 152 | 1 | 1/78 | 1.08% | 1609 | 421 | 非原版 | tiger field |
| 佩露夏 白虎 (777) | 加鲁卡 · 152 | 1 | 1/78 | 1.08% | 1610 | 421 | 非原版 | tiger field |
| 萨格鲁 黑虎 (778) | 加鲁卡 · 151 | 1 | 1/91 (1.10%) | 0.89% | 1611 | 416 | 非原版 | original wild is 伊甸大陆 (not in our data) |
| 葛雷基欧 地年兽 (901) | 萨伊那斯 · 38 | 1 | 1/127 (0.79%) | 0.79% | 1794 | — | 非原版 | festive: the field at 霍特尔村's gate (Lv1–15), which already has original weight-1 rare groups; not 萨姆吉尔's starter field, so its rolls stay as they were |
| 葛雷洛比 水年兽 (902) | 萨伊那斯 · 38 | 1 | 1/127 | 0.79% | 1795 | — | 非原版 | same |
| 葛雷吉鲁 火年兽 (903) | 萨伊那斯 · 38 | 1 | 1/127 | 0.79% | 1796 | — | 非原版 | same |
| 葛雷马恩 风年兽 (904) | 萨伊那斯 · 38 | 1 | 1/127 | 0.79% | 1797 | — | 非原版 | same |
| 黑乌力 黑猪 (5) | 萨伊那斯 · 56 | 1 | 1/97 (1.03%) | 0.93% | 475 | 255 乌力 Lv15–20 | 非原版 | the 乌力 field, Lv15–20 |

Scaled areas: 500/639 ×2, 500/652 ×2, 500/638 ×3, 地下6楼 ×14, 地下7楼 ×17, 地下8楼 ×14, 地下20楼 ×3, 萨伊那斯 56 ×8.

Already Lv.1 in the original, so nothing is added: 布林帖斯 (地下18楼), 邦恩多斯 (龙穴), 布拉奇多斯 (沙姆岛), 贝鲁卡 / 贝鲁伊卡 (加鲁卡), 格鲁西斯 (吉鲁岛).

## Left out, and later

- **Later, when their maps are imported**, these become original Lv.1 spots on their own: 奥卡洛斯 on 31806 (阿斯玛鲁矿山, area 363), 加宝格恩 on 30702 (area 605), 布洛多斯 on 5507 (area 658). The 飞龙 home 30701–30703 (帖拉格恩, 加宝格恩, 迪布恩 Lv80–82) would suit 帖拉格恩 better than 漆黑的洞窟. 萨格鲁's original 伊甸大陆 (蒙达山) is not in the reference data at all.
- **Later (8.0-era) variants are not added**: only the classic pets asked for are. Template numbers from about 700 up are later additions to `enemybase.txt` (the 2.5-era pets are 1–~600), and these have no Lv.1 spot here: 水5火5 巴朵兰恩 724, 斑尼迪克 1036 (暴龙队 variant), 朵巴奈特 811/979, 阿米朵 813, 布洛多多 1042, 邦司凉朵 814, 嘎吱拉 796, 哥斯哥斯 797, 蒙哥拉斯 798, 可可恩 803, 克洛恩 804, 布兰恩 805, 迪布恩 806, 玛斯贝卡 779. Exceptions asked for by name: 金暴 812, 蓝虎 776, 白虎 777, 黑虎 778, 机豹 968.
- The 新手 tigers (161–164) are weaker starter gifts, so they are left out. 吉比 (910) and 凯恩 (918) share the 年兽 album page but are not 年兽.
- Only 黑羊 was asked for in 布伊德系. 布伊德 (311) and 摩娜西普 金羊 (312) still have no wild spot, and 卡伊霍恩 / 拉伊霍恩 only Lv95–105.

## Verification

- `python3 -m unittest discover -s tools -p test_import_encounters.py`: merge rules, refusals, and every shipped share between 0.5% and 1.5%.
- `res://tests/rare_encounters_test.gd`: every addition in its area at Lv.1 with weight 1, companion 1:1 and the template's capture parameter; the reference group untouched; seeded rolls meet every added pet; a seeded GDScript hunt finds a Lv.1 左迪洛斯 and the battle authority captures it.
- `res://tests/fast_hunt_test.gd`: C helper and GDScript roll the same 3000 rolls for the added 左迪洛斯 at 500/639.
- `res://tests/pet_encyclopedia_test.gd`: each spot is a reachable Lv.1 location of its species, labelled 补充 / 原版无野外，非原版.

## Rebuild

After changing `rare-encounters.json` or the importer:

```sh
python3 tools/import_encounters.py
python3 tools/build_training_spots.py
python3 tools/build_level_one_spots.py
python3 tools/build_species_potential.py   # wild_level drops to 1 for the added pets
```
