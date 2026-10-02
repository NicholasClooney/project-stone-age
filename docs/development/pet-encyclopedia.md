# 宠物大全

A species book like the classic fan-site pet grids: every pet species of the imported encounter tables, grouped into families (系), with its original battle sprite, template stats, full-grade Lv.120 prediction and where it lives. This project's addition; the original client only had the per-player 宠物相簿.

573 species: 442 from the reference server's templates and 131 later pets from the 8.5 client's album that have 8.0 art but no original stats ([8.0 pets](../reverse-engineering/pets-8.0.md)). With the 8.0 data imported, 571 have a picture; 亚瑟力 and 夏莫 show 无图 because one of their frames points at a bitmap missing from the original data. Without the 8.0 data about half show 无图.

## Opening it

- **游戏助手 → 宠物大全**, or its shortcut **B** (rebindable on 设置 → 快捷键).
- The pet window's tool column: **宠物大全** beside 自动抓极品 opens on the selected pet's species.
- Esc goes back from a species page, then closes the window. It does not open during a battle.

## Views

- **网格**: families in album order, one cell per species with its standing battle frame and name. Cells show 已有N for species you own, the player name (蓝人龙, 机暴…), for two species with one name (巴朵兰恩 #303 and its stronger #724) the template number, or 8.0 for the later pets without stats.
- **列表**: species ranked by the **mean Lv.120 三围合** (attack + defence + speed) of a full-grade pet (all four growth weights +2) caught at Lv.1 and trained to 120. Columns: picture, name, 系, 三围合 mean, 前0.1% (the 三围合 the best one in a thousand reaches), mean attack / defence / speed / HP, 成长级, 可抓, 出现, and 瞬移去抓 to the best place. Click a header to sort by it, again to reverse. 30 per page.
- **Species page**: the animated sprite (◀ 转向 ▶ or click it), the family's other species, 原表资料 (for the 8.0 pets: 没有原版数值, and no prediction) (初始系数, 野生成长, 成长级, the four weights 体力/腕力/耐力/速度 and their +2 values, elements, capture), the Lv.120 prediction (mean, 前1%, 前0.1%, sample maximum and mean attack/defence/speed/HP), a second prediction for a pet caught at the lowest wild level when that is above 1 (野生最低 Lv.X), your own pets of the species with their best exact Lv.120 三围合 and attack, and every wild location.
- Search matches names, player names and family names; **只看野外可抓** hides species with no capturable wild spawn.
- **经典宠物** shows only the pets players remember from the original ([classic pets](../product/classic-pets.md), `client/data/classic-pets.json`). The grid groups them by category (PK 与战宠, 经典骑宠, 稀有、任务和活动宠, 可爱与新手) instead of family, with the 俗称 under each cell; the list keeps the file's order (no sorting) with 俗称, 为什么经典, 这里能不能抓 (the wild places here, 原版不能野外捕捉 plus how the original gave it out, or 原版可野外捕捉 when only our data lacks the spawn) and 瞬移去抓. A classic pet our data has no template for (摩卡) shows as a greyed 资料里没有 cell or row. The species page of a classic pet has a 经典宠物 card above 出现地点. Species without a player name get the 俗称 as their alias, so search finds 金飞, 白鲨 and the rest.
- **全部 / 已拥有 / 未拥有** filters by the species of the character's carried and stored pets (`owned_counts`, read from `world.session.snapshot()` when the window opens). It combines with the search, 只看野外可抓 and 经典宠物. In 已拥有 the list's 出现 column becomes **我的**: how many you have and the best one's exact Lv.120 三围合 (computed only for the rows on the page).

成长级 is the template's growth rank from its weight sum (≥100, 95, 90, 85, 80: rank 0 to 4, else 5); rank r levels up with a roll of 450+20r to 500+20r percent (`progression.gd`). It is not the per-pet 成长档 (−2 to +2 birth grades) that 自动抓极品 filters on.

## Locations and 瞬移去抓

Locations are the ordinary encounter areas the hunt uses (`pet_hunt_rules.gd` candidates: positive weights, no event or item gate), with the level range and whether that row can be captured. Species with none show **无野外出现** (special pets, event and quest pets, later-version designs; see [special pets](../reverse-engineering/special-pets.md)). Rare Lv.1 spots added from `client/data/rare-encounters.json` are separate locations tagged **补充 · 原版此区只有高等级的** (the pet lives in that area at a higher level in the original) or **原版无野外，非原版**; see [rare Lv.1 encounters](../reverse-engineering/rare-level-one-encounters.md).

**瞬移去抓** uses the verified landing cell of that area from `client/data/training-spots.json` (the same cells as 刷怪传送), rechecks the area and the landing, teleports, and opens 自动抓极品 with the species as target and on its 属性条件 page. The Lv.1 limit is switched on when that area has Lv.1 rows and off otherwise. Areas on maps not imported yet, or whose groups lack battle art, show why they cannot be reached. It is refused during a battle, a map change, or while 自动练级 / 自动抓极品 runs. A web client downloads the target map's packs first (the landing check needs the map file) and reopens 宠物大全 with 地图素材下载失败 if that fails. Both pickers of 自动抓极品 show the species at once; a remote client does not wait for the saved settings to come back.

## Family grouping

`client/data/pet_families.json` (`python3 tools/build_pet_families.py`, needs `references/` and the imported catalog) follows the 8.5 client's pet album, `PetAlbumTbl` in `systeminc/petName.h`: the album lists pets in pages of eight, one family per page (four base forms and four later variants), so album number ÷ 8 is the family. A template whose name is not in the album joins the family of a template with the same battle sprite (森林乌力 → 乌力系, 火的守护兽 → 人龙系); nine left over go to 其他. A few well-known families carry their player names (乌力系, 布伊系, 加美系, 龟系, 人龙系, 虎系, 暴龙系, 年兽系); the rest are named after the page's first pet. Later album pages (from 贝里莱欧系 on) mix unrelated pets, as the album does.

The 131 album pets without a template are templates 10000 + album number and join their album page like the rest; from about 布伊酷系 on, those pages are mostly 8.0 pets. A family is named after its page's first pet whose name has no digit (弗丽雅系, not 变色龙2系).

Templates with the same name, sprite, initial value and weights (巴朵兰恩 106 and 303) are one species; the one seen most in the wild names it. Template 724 (巴朵兰恩 with initial 37) stays separate.

## Data and code

| File | Role |
| --- | --- |
| `client/scripts/pet_encyclopedia.gd` | Functional core: entries, families, locations, ranking, owned counts |
| `client/scripts/pet_encyclopedia_menu.gd` | The window; `travel` and `open_hunt` are test seams |
| `client/scripts/pet_thumbnails.gd` | Still frames cut from sprite sheets, cached; the sheet is released |
| `client/data/species_potential.json` | Lv.120 predictions, see [species potential](../technical/species-potential.md) |
| `client/data/pet_families.json` | Family grouping |
| `client/data/classic-pets.json` | 经典宠物: 俗称, reason, original source, sources; attached by `load_classic` |

Pictures: every sprite's animations are in its own file, `battle/sprites/<sprite>.json` (`client/scripts/battle_art.gd`, [runtime files](../technical/sprite-sheets.md#runtime-files)); a picture reads the file without keeping it, and the web build ships most pets' files in the sprite's own pack. Only the cells on screen are cut, within 8 ms per frame; a sheet (about 2048 × 1024) is loaded, one frame copied and the sheet dropped, so the grid never holds hundreds of sheets. On the web a missing sprite pack is prefetched in the background and the cell fills in when it arrives; the species page downloads its sprite with a label. Species without imported battle art show 无图.

Test: `pet_encyclopedia_test` (real catalog and data files; fake teleport and hunt for the rules, one real 瞬移去抓 into 自动抓极品; art for all but two species, the 8.0 pets' pages). `rare_teleport_test`: a remote client with web-like packs clicks 瞬移去抓 for 奥卡洛斯 (mouse input on the button), downloads, lands on ground and opens 自动抓极品 on it; a failed download for 艾迪希洛 reopens 宠物大全.

## Thumbnails

The grid and list pictures are pre-cut at import time by `tools/build_pet_thumbs.py`: each battle sprite's first standing frame (animation 3, facing 1, else 0), at most 128 px, packed into 1024 px atlases under `assets/legacy/thumbs/` (`index.json` maps sprite → atlas and region; 641 sprites, 5 atlases, about 4 MB). `scripts/pet_thumbnails.gd` serves them as `AtlasTexture`s and only falls back to cutting a sprite's sheet for a sprite missing from the index. On the web each atlas is its own pack (`thumbs-<n>`): the game prefetches them quietly after the start area, and 宠物大全 shows a non-blocking 「宠物图 x / y MB」 bar while any is still downloading; pictures appear as their atlas arrives. Re-run the tool after changing battle sheets (`scripts/setup-original-data.sh` does).

## 已拥有个体与仓库取出

品种详情的「我的」卡片逐只显示随身与仓库宠物的当前等级、攻防敏、三围合、当前／最大血量及稳定 `pet_id`。位置为随身或仓库；随身宠物按快照的索引补充出战和骑乘，同一只宠物可同时标注两种状态。匹配沿用 `entry_for_pet` 的真实模板／`species_key`，不会把改成同名的其他品种算进来。

仓库个体的「移到随身」通过 `world.link.request` 发送既有 `retrieve_pet_by_id` 命令。客户端先在当前快照确认 UID 仍在仓库，服务器再按 UID 查找当前索引；不复制个体，不改 UID，也不增加新的战斗或组队规则。服务器满栏、捕捉预留栏位及其他拒绝原因显示在窗口反馈区。远端界面不依赖本地 backend。

打开的详情按 UID 保留个体行和按钮，快照更新只改资料与位置，保留悬停对象与滚动偏移；只有所选品种变化才创建该品种的新内容。列表的统计刷新保留当前页和行，所有权过滤的品种集合变化时才重新筛选。详情使用统一的有界滚动区，窄屏纵向排列资料与地点，缩略图仍走原 atlas、调色板和素材下载流程。

`encyclopedia_owned_pets_test` 使用真实本机 GameScene、backend/session 与端口 0 WebSocket，两台无本地 backend 的远端设备；通过实际鼠标输入验证取出、UID 与属性保留、位置同步、满栏及战斗捕捉空位拒绝，并检查 390×844 布局几何。无窗口测试不验证渲染像素。

## 动态骑宠卡

`PetEncyclopedia.load_classic(data, riding_data)`按有效原版pairs生成骑宠分类，保留其他静态分类。`variant_ids`为同sprite的独立成长entry集合，`entry_id`为主条目；必须经`by_template`解析原表ID，不能把sprite相同等同于成长相同。当前25外观／28成长条目，排除4只新手虎。静态来源记录仍供其他分类和详情使用；新生成的成员只补原版骑图依据。

`classic_filtered`对卡内每个变体应用搜索、可抓、拥有筛选，选择匹配的主入口。网格、经典列表和详情均提供同图变体按钮与当前造型骑乘提示。UI只读`world.session.snapshot()`，状态变化时刷新造型标签，避免每帧复制整个存档。面板重建先清空旧内容再计算宽度，并在布局后收缩，支持390×844。

`classic_riding_catalog_test`使用端口0真实WebSocket与无本地backend的GameScene，验证25名单、28变体、原分类保留、动态新增pairs、拥有变体筛选、换造型提示刷新、鼠标点击变体入口及三个补充地点的远端瞬移和搜宠目标。默认无窗口；经明确授权，可用 `STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/classic_riding_catalog_test.gd -- --visual-review` 在静音屏幕外窗口抓取真实渲染PNG（`/private/tmp/tmux-agents/ride-classic-audit/shots/`）。390×844为真实viewport，不是事后缩图；PNG不提交。
