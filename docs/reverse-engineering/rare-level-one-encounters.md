# Rare Lv.1 encounters in high-level areas

## 原版骑图三只Lv1补充

为动态经典骑宠增加三个无同伴、区域weight1的单独组，均为`origin: added`（补充·非原版）。每组只有一只Lv.1宠物。原模板、原enemy行和捕获参数不改。

|宠物／template|原Lv1 enemy／flag|使用enemy／group|新增map／area／安全格|普通组权重占比|
|---|---|---|---|---|
|瑞里西尔809|1642／0|clone90211／91111|萨伊那斯100／38／623,178|1/131≈0.763%|
|史卡鲁1110|2138／1|2138／91112|五十年前波拉岛500／639／400,400|1/119≈0.840%|
|罗多克雷1095|2119／1|2119／91113|五十年前波拉岛500／638／255,326|1/96≈1.042%|

证据是`references/chenmingbiao-stone-age/gmsv/data/enemy.txt`的1218、1613、1598行，分别为1642/template809、2138/template1110、2119/template1095，等级均1–1、数量均1。模板在`enemybase.txt`607、897、886行，pet_flag均1，捕获参数分别-1、11、0；-1仍进入正常捕获公式。625/template的新手瑞里西尔及20/77史卡鲁为pet_flag0模板，不用于新增宠物。625虽有Lv1敌行2191，却是完全不同的新手参数；20/77只找到Lv120/160敌行，不制造Lv1原行。

上述三个宠物在固定参考group表均无引用。瑞里西尔安排在同系火鸡、奇宝区域；另两只的同系在已导入地图没有原生野外点，因此岛上地点属于本作稀有骑宠搜集安排，不声称恢复原版分布。现有权重已适合约1%，无需新scale，不加混合组，也不改变原行1642的pet_flag0。克隆使用现有`clones`机制。

重建链：`python3 tools/import_encounters.py`、`python3 tools/build_training_spots.py`、`python3 tools/build_level_one_spots.py`。三只的百万样本Lv1预测已存在且模板未改，`species_potential.json`只将三者wild_level从0更新为1，保留全部原样本数值，不必重新运行全量模拟。三只battle sprite均已导入。

Python导入测试对照原表核验原模板／原敌行完整不变、单独组与权重。`rare_encounters_test`对所有补充点执行真实有效区域、roll及捕获结算校验；`classic_riding_catalog_test`实际远端点击三个「瞬移去抓」，核对map与两个hunt目标字段。

## 2026-10-02 同系补全

新增11个单独Lv.1补充组：四只后期飞龙分散于地下6/7/8/10楼，扑满乌力/乌力莱德/乌力固力在萨伊那斯乌力区，玛斯贝卡在加鲁卡老虎区，邦诺斯娜/杨格斯/迪基格斯在吉鲁人龙区。七条原本不可捕获的敌行采用明确标注的可抓克隆，原行和模板不改。经典名单补14条，原已收录的不重复。

逐只ID、原行、区域、分配理由和骑乘原图核查见 [同系补全](family-lv1-completion.md)。这些新增捕获点均为「补充·非原版」，不是恢复原版野外分布。

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

- Each addition is a new group like group 751: **{the Lv.1 row, weight 1; a companion, weight 1}** with area weight **1**. The companion is a high-level enemy already in the area's original groups: the same pet where the area has it, else its closest kin there. The 年兽 have none (they appear alone). Group ids are 91001+ (alone groups 92001+, below), and each group carries `rare: {origin, template_id, enemy_id, reason}`.
- The Lv.1 row is the pet's own original Lv.1 row: a dungeon Lv.1 entry where one exists, else the unused Lv.1 row. When the only Lv.1 row is not capturable (pet_flag 0), or there is none, a **clone** gets id 90001+, level 1–1, capturable, at most one per troop and `clone_of` the source row. Everything else stays as in the source row. Capture difficulty is always the template's own `capture_resistance`.
- Areas whose ordinary weights add up to much less than 100 get **scaled** by a whole factor (`areas` in the file, `weight_scale` on the area), like the original's own Lv.1 floors. That changes no ratio between original groups. Resulting shares are 0.77%–1.23% per group (reference 0.99%), after the alone groups. A test keeps every share between 0.5% and 1.5%.
- **Alone groups.** Every addition with a companion also has a second group holding only its Lv.1 row (`alone_group_id`, ids 92001+ = the companion group's id + 1000, `rare.alone: true`), again with area weight 1: the original's other Lv.1 shape, the single Lv.1 groups of 加鲁卡 (271, 275), 吉鲁岛 (435, 443) and 沙姆岛 (528). Copies follow the Lv.1 row's own max_count, as in those groups: 1 for most rows and clones, 2 for 奥卡洛斯, 邦浦洛斯, 布鲁顿, 加格, 贝洛恩 and 格尔格, 3 for the unused rows that the original gives max 3 (巴朵兰恩, 左迪洛斯, 邦达霍恩, 帖拉格恩, 洛卡伦恩, 朵拉比斯, 帖拉所伊朵, 金格萨贝鲁, 黑乌力, 摩娜西普); all of them Lv.1. The rows stay original, so the copies are not capped at 2. The 年兽, 吉比, 鲁比 and 蒙奇 have no companion and are alone already.
- **Why both.** Auto hunting (自动抓宠, 找宠) only weakens and catches its target, so it skips troops with an enemy above Lv.1 by default (`hunt.clean_only`, see [pet-hunt-helper.md](../development/pet-hunt-helper.md#只进无其他敌人的遇敌)). With only the companion groups a clean troop came from the rare roll that picked the Lv.1 pet alone (about 1 in 8 of the pet's troops at 五十年前波拉岛 639). The alone group brings a clean hunt back to about the reference's rate (0.83% per battle, here 0.88%–1.32%), and the pet's rate over all troops rises to 1.5%–2.3%. The companion groups stay: they copy the reference group 751, `mixed_if_stats` and a future clear-then-capture party (docs/product/ideas.md) use them, and under the default they only cost scanning, since the hunt sees the troop before any battle.
- On the 地图导航 map these spots are labelled and outlined in violet instead of the Lv.1 green (`PetEncyclopedia.level_one_areas` returns them as separate `added` entries); the legend explains the colour.
- `origin` is `original_area` (**补充**) when the pet has an original wild row in that area at a higher level, and `added` (**原版无野外，非原版**) when it has no original wild area on an imported map. Original Lv.1 rows (布林帖斯 in 地下18楼, 邦恩多斯 in the 龙穴, 布拉奇多斯 on 沙姆岛, the tigers) are unchanged and unmarked.

## Spots

Map 500 五十年前波拉岛 is reached with 地图导航 or 宠物大全's 瞬移去抓. "Per battle" means per encounter in that area (40,000 seeded rolls with the merged catalog): **any** is a troop with the Lv.1 pet in it, **clean** one where every enemy is Lv.1, which is what a hunt with 只进无其他敌人的遇敌 (the default) can enter. "1 + 1" is the companion group and the alone group, each weight 1 of the total.

| Pet (template) | Map · area | Lv | Weight (share) | Per battle: any / clean | Lv.1 row | Companion | Origin | Why here |
|---|---|---|---|---|---|---|---|---|
| 巴朵兰恩 红暴 (303) | 五十年前波拉岛 · 639 (whole island) | 1 | 1 + 1 of 118 (0.85% each) | 1.53% / 1.02% | 352 | 1473 红暴 Lv90–95 | 补充 | original Lv90–95 red rex area |
| 奥卡洛斯 绿暴 (301) | 五十年前波拉岛 · 652 (龙穴) | 1 | 1 + 1 of 112 (0.89% each) | 1.62% / 1.01% | 1037 | 1474 绿暴 Lv90–95 | 补充 | original Lv90–95 green rex area |
| 斯天多斯 绿雷龙 (254) | 五十年前波拉岛 · 652 | 1 | 1 + 1 of 112 (0.89% each) | 1.57% / 0.97% | 1450 | 1471 | 补充 | original Lv90–95; 1450 is 1451's twin |
| 布洛多斯 (251) | 五十年前波拉岛 · 638 | 1 | 1 + 1 of 95 (1.05% each) | 1.72% / 1.10% | 1557 | 1465 | 补充 | original Lv80–90 thunder dragon area |
| 加宝格恩 (273) | 漆黑的洞窟 地下9楼 · 619 | 1 | 1 + 1 of 103 (0.97% each) | 1.84% / 1.15% | 1368 | 1388 | 补充 | original Lv88–90 |
| 卡特利奴 卡虎 (524) | 加鲁卡 · 143 | 1 | 1 + 1 of 94 (1.06% each) | 2.02% / 1.26% | clone of 539 | 415 贝鲁卡 | 补充 | original quest encounter (走失的红虎, item-gated Lv15) is here |
| 左迪洛斯 蓝暴 (302) | 五十年前波拉岛 · 639 | 1 | 1 + 1 of 118 (0.85% each) | 1.51% / 0.94% | 351 | 1473 | 非原版 | dragons live on this island |
| 斑尼迪克 金暴 (812) | 五十年前波拉岛 · 639 | 1 | 1 + 1 of 118 (0.85% each) | 1.52% / 0.94% | clone of 1645 | 1473 | 非原版 | rex island |
| 邦达霍恩 黑羊 (315) | 五十年前波拉岛 · 652 | 1 | 1 + 1 of 112 (0.89% each) | 1.60% / 0.97% | 484 | 1463 卡伊霍恩 | 非原版 | its family (卡伊霍恩, 拉伊霍恩) lives only here |
| 帖拉格恩 (271) | 漆黑的洞窟 地下6楼 · 616 | 1 | 1 + 1 of 100 (1.00% each) | 2.10% / 1.21% | 338 | 1388 加宝格恩 | 非原版 | original wild only on 30701–30703 (not imported); its kin 加宝格恩 lives on 地下6–10楼 |
| 洛卡伦恩 (272) | 地下7楼 · 617 | 1 | 1 + 1 of 104 (0.96% each) | 1.76% / 1.06% | 339 | 1388 | 非原版 | flying dragon floors |
| 朵拉比斯 金飞 (274) | 地下8楼 · 618 | 1 | 1 + 1 of 100 (1.00% each) | 2.10% / 1.21% | 341 | 1388 | 非原版 | flying dragon floors |
| 艾迪希洛 机豹 (968) | 地下19楼 · 629 | 1 | 1 + 1 of 103 (0.97% each) | 1.83% / 1.12% | clone of 1946 | 1396 拉可拉斯 | 非原版 | the machine pets go with 机暴's cave; this floor already has an original Lv.1 |
| 帖拉所伊朵 机暴 (304) | 地下20楼 · 630 | 1 | 1 + 1 of 122 (0.82% each) | 1.50% / 0.88% | 353 | 1398 布林帖斯 | 非原版 | the cave's guardian (bosses 1404 黑色帖拉所伊朵, 1942 钻石帖拉所依朵); deepest floor |
| 金格萨贝鲁 金虎 (194) | 加鲁卡 · 152 | 1 | 1 + 1 of 81 (1.23% each) | 2.19% / 1.32% | 310 | 417 贝鲁卡 Lv18–20 | 非原版 | the tigers' home outside 琉璃洞窟, highest tiger field |
| 普鲁夏 蓝虎 (776) | 加鲁卡 · 152 | 1 | 1 + 1 of 81 (1.23% each) | 2.25% / 1.23% | 1609 | 421 | 非原版 | tiger field |
| 佩露夏 白虎 (777) | 加鲁卡 · 152 | 1 | 1 + 1 of 81 (1.23% each) | 2.24% / 1.30% | 1610 | 421 | 非原版 | tiger field |
| 萨格鲁 黑虎 (778) | 加鲁卡 · 151 | 1 | 1 + 1 of 92 (1.09% each) | 2.05% / 1.26% | 1611 | 416 | 非原版 | original wild is 伊甸大陆 (not in our data) |
| 葛雷基欧 地年兽 (901) | 萨伊那斯 · 38 | 1 | 1 of 130 (0.77% each) | 0.85% / 0.85% | 1794 | — | 非原版 | festive: the field at 霍特尔村's gate (Lv1–15), which already has original weight-1 rare groups; not 萨姆吉尔's starter field, so its rolls stay as they were |
| 葛雷洛比 水年兽 (902) | 萨伊那斯 · 38 | 1 | 1 of 130 (0.77% each) | 0.72% / 0.72% | 1795 | — | 非原版 | same |
| 葛雷吉鲁 火年兽 (903) | 萨伊那斯 · 38 | 1 | 1 of 130 (0.77% each) | 0.82% / 0.82% | 1796 | — | 非原版 | same |
| 葛雷马恩 风年兽 (904) | 萨伊那斯 · 38 | 1 | 1 of 130 (0.77% each) | 0.75% / 0.75% | 1797 | — | 非原版 | same |
| 黑乌力 黑猪 (5) | 萨伊那斯 · 56 | 1 | 1 + 1 of 100 (1.00% each) | 1.93% / 1.13% | 475 | 255 乌力 Lv15–20 | 非原版 | the 乌力 field, Lv15–20 |
| 利则诺顿 绿人龙 (91) | 吉鲁岛 · 473 | 1 | 1 + 1 of 103 (0.97% each) | 1.79% / 1.14% | 1138 | 1187 Lv51–53 | 补充 | its most common place (49.5%); the area already has an original weight-1 Lv.1 group (627). 1138 is the Lv.1 row of dungeon 21013 (not imported) |
| 邦浦洛斯 灰人龙 (93) | 吉鲁岛 · 311 | 1 | 1 + 1 of 103 (0.97% each) | 1.73% / 1.11% | 979 | 980 Lv43–45 | 补充 | lowest wild level. 979 is the original's own 吉鲁岛 Lv.1 row (area 332, see below) |
| 布鲁顿 黄人龙 (95) | 吉鲁岛 · 311 | 1 | 1 + 1 of 103 (0.97% each) | 1.78% / 1.12% | 981 | 982 Lv43–45 | 补充 | same; 981 is the original's area 333 Lv.1 row |
| 加格 白鲨 (223) | 五十年前波拉岛 · 659 | 1 | 1 + 1 of 102 (0.98% each) | 1.76% / 1.11% | 446 | 1491 Lv90–95 | 补充 | its only wild place on an imported map (659–661 share one group; 659 has the highest priority). 446 is dungeon 10203's Lv.1 row |
| 贝洛恩 (41) | 阿布的洞窟地下4楼 · 76 | 1 | 1 + 1 of 92 (1.09% each) | 1.96% / 1.23% | 266 | 278 Lv22–24 | 补充 | lowest wild level (地下3/4楼); 地下3楼's area 74 lists two groups missing from group.txt, 76 does not. 266 is dungeon 10101's Lv.1 row |
| 格尔格 红猩猩 (144) | 漆黑的洞窟 地下5楼 · 615 | 1 | 1 + 1 of 103 (0.97% each) | 1.81% / 1.11% | 994 | 1384 Lv85–87 | 补充 | the floor already weighs 101 with an original weight-1 Lv.1 group (736). 994 is dungeon 31204's Lv.1 row |
| 卡卡金宝 红蛙 (234) | 阿斯玛鲁矿山6楼 (31806) · 362 | 1 | 1 + 1 of 103 (0.97% each) | 1.89% / 1.16% | 1682 | 1036 | 非原版 | original wild only on the Giru dungeons 30601–30606 (not imported); its kin 奇卡宝斯 has Lv1 and Lv60–63 here |
| 摩娜西普 金羊 (312) | 五十年前波拉岛 · 652 | 1 | 1 + 1 of 112 (0.89% each) | 1.72% / 1.00% | 355 | 1463 卡伊霍恩 | 非原版 | quest pet; with its kin 黑羊 |
| 乌力王 (170) | 萨伊那斯 · 56 | 1 | 1 + 1 of 100 (1.00% each) | 1.85% / 1.02% | 2492 | 255 乌力 | 非原版 | no wild spot; with 黑乌力 on the 乌力 field |
| 吉比 小GP (910) | 萨伊那斯 · 38 | 1 | 1 of 130 (0.77%) | 0.72% / 0.72% | 1804 | — | 非原版 | card-pack pet; alone, beside the 年兽 (same album page) |
| 鲁比 大GP (965) | 萨伊那斯 · 38 | 1 | 1 of 130 | 0.86% / 0.86% | 1926 | — | 非原版 | paired with 吉比 |
| 蒙奇 (969) | 萨伊那斯 · 38 | 1 | 1 of 130 | 0.72% / 0.72% | clone of 1947 | — | 非原版 | with 吉比 and 鲁比 |

Scaled areas: 500/639 ×2, 500/652 ×2, 500/638 ×3, 地下6楼 ×14, 地下7楼 ×17, 地下8楼 ×14, 地下20楼 ×3, 萨伊那斯 56 ×8, 吉鲁岛 311 ×33, 500/659 ×10, 阿布的洞窟地下4楼 76 ×2.

Already Lv.1 in the original, so nothing is added: 布林帖斯 (地下18楼), 邦恩多斯 (龙穴), 布拉奇多斯 (沙姆岛), 贝鲁卡 / 贝鲁伊卡 (加鲁卡), 格鲁西斯 (吉鲁岛).

## Left out, and later

- **Later, when their maps are imported**, these become original Lv.1 spots on their own: 奥卡洛斯 on 31806 (阿斯玛鲁矿山, area 363), 加宝格恩 on 30702 (area 605), 布洛多斯 on 5507 (area 658). The 飞龙 home 30701–30703 (帖拉格恩, 加宝格恩, 迪布恩 Lv80–82) would suit 帖拉格恩 better than 漆黑的洞窟. 萨格鲁's original 伊甸大陆 (蒙达山) is not in the reference data at all.
- **Later (8.0-era) variants are not added**: only the classic pets asked for are. Template numbers from about 700 up are later additions to `enemybase.txt` (the 2.5-era pets are 1–~600), and these have no Lv.1 spot here: 水5火5 巴朵兰恩 724, 斑尼迪克 1036 (暴龙队 variant), 朵巴奈特 811/979, 阿米朵 813, 布洛多多 1042, 邦司凉朵 814, 嘎吱拉 796, 哥斯哥斯 797, 蒙哥拉斯 798, 可可恩 803, 克洛恩 804, 布兰恩 805, 迪布恩 806, 玛斯贝卡 779. Exceptions asked for by name: 金暴 812, 蓝虎 776, 白虎 777, 黑虎 778, 机豹 968.
- **Classic pets whose only wild rows are on maps not imported yet** get nothing, because no imported area has them at any level: 石龟 (54, dungeons 11001–11005 Lv1–15 and 30501–30511), 卡达鲁卡斯 绿穿山甲 (81, 10601–10605 Lv1–15, 30301–30307), 卡卡金宝 红蛙 (234, 30601–30606, with an original Lv.1 row 1682). They become original Lv.1 spots once those dungeons are imported. The Giru import (`tools/world_regions/giiru.json`) walks into some of their higher-level dungeons as `kind: dungeon` maps, which the spot builders do not index (only `training` maps and 100/200): 石龟 Lv55–57 on 30501 巴那姆的洞窟, 卡达鲁卡斯 Lv80–82 and 格尔格 Lv82–84 on 30301/30302. If those maps become hunt targets, 石龟 and 卡达鲁卡斯 can get a 补充 Lv.1 there (rows 502, 505). 31204 holds an original Lv.1 格尔格 (994, 1/41), and 31806 one for 奥卡洛斯 (1037); once they are indexed, the 格尔格 and 奥卡洛斯 additions can go. 乌力乌力 (2) is a starter whose only wild row is dungeon 10204 (Lv20–30). The classic entries with `original_wild: false` (吉比, 鲁比, 蒙奇, 摩娜西普, 乌力王) are not wild pets in the original; they have the 非原版 spots above.
- **吉鲁岛's own Lv.1 人龙**: the original puts Lv.1 邦浦洛斯 (group 438) and 布鲁顿 (group 440) at weight 1/101 in areas 332 and 333, small rects inside area 311 with the same priority 20. `encounter_catalog.gd area_at` keeps the first area on a priority tie, so 311 always wins and those groups are never rolled (地图导航 still labels them green). The server source for the original tie rule is not in `references/`. If it turns out to pick the later area, 332/333 become reachable and the two 311 additions can go.
- The 新手 tigers (161–164) are weaker starter gifts, so they are left out. 吉比 (910) and 凯恩 (918) share the 年兽 album page but are not 年兽.
- Only 黑羊 was asked for in 布伊德系. 布伊德 (311) and 摩娜西普 金羊 (312) still have no wild spot, and 卡伊霍恩 / 拉伊霍恩 only Lv95–105.

## Verification

- `python3 -m unittest discover -s tools -p test_import_encounters.py`: merge rules (alone groups too), refusals, unique group ids, an alone group for every addition with a companion, and every shipped share between 0.5% and 1.5%.
- `res://tests/rare_encounters_test.gd`: every addition in its area at Lv.1 with weight 1, companion 1:1 and the template's capture parameter; each one with a companion also alone (weight 1, marked, seeded rolls of that group give only Lv.1 copies of the pet); the reference group untouched; seeded rolls meet every added pet; every 补充 addition sits beside the same pet at a higher level; every classic pet with a wild spot has a Lv.1 spot; a seeded GDScript hunt finds a Lv.1 左迪洛斯 and the battle authority captures it.
- `res://tests/fast_hunt_test.gd`: C helper and GDScript roll the same 3000 rolls for the added 左迪洛斯 at 500/639 and for 邦浦洛斯 in the scaled 吉鲁岛 311.
- `res://tests/pet_encyclopedia_test.gd`: each spot is a reachable Lv.1 location of its species, labelled 补充 / 原版无野外，非原版; 利则诺顿's best place is its 补充 Lv.1 on 吉鲁岛. `res://tests/map_labels_test.gd`: 吉鲁岛's 补充 人龙 labels use the added colour.

## Rebuild

After changing `rare-encounters.json` or the importer:

```sh
python3 tools/import_encounters.py
python3 tools/build_training_spots.py
python3 tools/build_level_one_spots.py
python3 tools/build_species_potential.py   # wild_level drops to 1 for the added pets
```
