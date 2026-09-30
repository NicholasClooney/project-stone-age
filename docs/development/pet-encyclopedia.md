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

成长级 is the template's growth rank from its weight sum (≥100, 95, 90, 85, 80: rank 0 to 4, else 5); rank r levels up with a roll of 450+20r to 500+20r percent (`progression.gd`). It is not the per-pet 成长档 (−2 to +2 birth grades) that 自动抓极品 filters on.

## Locations and 瞬移去抓

Locations are the ordinary encounter areas the hunt uses (`pet_hunt_rules.gd` candidates: positive weights, no event or item gate), with the level range and whether that row can be captured. Species with none show **无野外出现** (special pets, event and quest pets, later-version designs; see [special pets](../reverse-engineering/special-pets.md)).

**瞬移去抓** uses the verified landing cell of that area from `client/data/training-spots.json` (the same cells as 刷怪传送), rechecks the area and the landing, teleports, and opens 自动抓极品 with the species as target and on its 属性条件 page. The Lv.1 limit is switched on when that area has Lv.1 rows and off otherwise. Areas on maps not imported yet, or whose groups lack battle art, show why they cannot be reached. It is refused during a battle, a map change, or while 自动练级 / 自动抓极品 runs.

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

Pictures: every sprite's animations are in its own file, `battle/sprites/<sprite>.json` (`client/scripts/battle_art.gd`, [runtime files](../technical/sprite-sheets.md#runtime-files)); a picture reads the file without keeping it, and the web build ships most pets' files in the sprite's own pack. Only the cells on screen are cut, within 8 ms per frame; a sheet (about 2048 × 1024) is loaded, one frame copied and the sheet dropped, so the grid never holds hundreds of sheets. On the web a missing sprite pack is prefetched in the background and the cell fills in when it arrives; the species page downloads its sprite with a label. Species without imported battle art show 无图.

Test: `pet_encyclopedia_test` (real catalog and data files; fake teleport and hunt for the rules, one real 瞬移去抓 into 自动抓极品; art for all but two species, the 8.0 pets' pages).
