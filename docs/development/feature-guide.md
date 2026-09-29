# Feature guide

What the restored game offers today, with pointers to the detailed notes. The [README](../../README.md) covers setup and how to play; [restoration status](restoration-status.md) tracks progress.

## Samgir and the world

- Original 160 × 160 Samgir map with 482 scenery objects, the original isometric projection and depth sorting, map/ADRN collision footprints, keyboard movement and click-to-walk with corner checks.
- Original eight-direction idle and walk frames, sit and wave. Character selection (**Tab** or **设置 → 换角色**) offers 47 original appearances with animated previews and matching club battle sprites. See [character selection](character-selection.md).
- Original `sabgm_t0.wav` village music with loop and volume controls; all four villages share it, and the wilderness follows its original map music markers.
- **音乐** (toolbar), the 电台: a radio of the whole original soundtrack (26 tracks from the 8.0 client, titled from the original `bgm_tbl`). Stations are 全部曲目, 收藏 and your own playlists; ☆ favourites a track, ＋ adds it to a playlist, and ↑ ↓ × edit a playlist. Each track loops until it has played for about 100 seconds, then the next one starts; 随机 shuffles; 单曲循环 keeps looping the current track until you pick another (上一首, 下一首 or a track in the list), remembered per device. About 10 seconds before the change the next track is chosen and downloaded in the background, so on the web only the very first track waits for a download. The radio plays through battles and map changes; 关闭电台 brings back the original scene music. Favourites and playlists belong to the character, so every device shares them; whether the radio is on, the station and the track are per device. The window does not pause the game and can be dragged, folded to a player bar or closed while the music continues.
- The four starting villages, both complete islands, linked village interiors and the original undersea route are visitable. The island crossing keeps its original reusable pass requirement. See [world scope and remaining services](m005-four-villages.md).
- 147 imported maps: the original 103, 35 training areas, and Giru's 福尔德村 (5000), 达那村 (5100) and seven ordinary interiors. Giru links to both villages and their interiors through original portals; reaching Giru itself still needs DEV travel. Dana restores 20 ordinary scene actors, including residents with original dialogue; other NPC services and quests are deferred. See [travel coverage](travel-and-leveling-assists.md).
- Original stone top controls, the wooden hover-reveal bottom menus, and a working original map window with live coordinates and player marker. See [classic UI evidence](m002-classic-ui.md).

## Adventure and battle

- Walking uses the original regional encounter probabilities, mixed groups, level ranges and wild stats. Captured animals keep their actual level and growth rolls. Special missions, dungeons, bosses and full special skills are deferred. See [ordinary encounters](../reverse-engineering/ordinary-encounters.md).
- The native battle panel supports independent targets across one to ten enemies, pet switching and withdrawal, learned skills, original miss/critical/counter effects and player → pet command selection. Player and pet stats use original fixed-point formulas and species growth; player levels grant three points to spend with the UP buttons in the status window. See [progression and battle](m006-progression-and-battle.md).
- The single-player loop has experience, levels, currency, a 30-pet collection with one active companion, three trainable original pet skills, healing items, a club, the original shop interior and merchant, one quest and a stronger finale. Progress autosaves and resumes. See [MVP scope and fidelity](m004-single-player-mvp.md).
- The original 超级饲育员 in Samgir's pet shop (map 1003 at 18,13) teaches 破除防御, 连续攻击 and 背水之战其之１ at their source prices.
- Capture probability, the short quest, shop stock and ordinary encounter timing still include explicit MVP rules; broader elemental and special skill behaviour is incomplete. Multiplayer parties, families and mail are deferred.

## Pets and riding

- On first launch **蓝人龙、金虎 and 红暴龙** join once; existing pets and progress stay intact.
- The pet window has five original rows per page, family filters, separate riding and battle states, an animated portrait (click it to turn the pet), a warehouse, same-species comparison, and a growth forecast against the species' theoretical ceiling (independently optimal attributes, not one attainable perfect pet). See [pet tools](pet-collection-growth.md) and [pet window](../reverse-engineering/pet-window.md).
- **怎样判断极品宠物？** See [宠物品质与成长窗口解读](../game-systems/pet-quality.md) for innate rolls versus actual growth, the +6 preset and default full-grade filter, forecast ranges and comparison limits.
- Ride from the pet window (**骑乘 · 名字**). Each appearance rides the two species the original table gives it, plus 左迪洛斯 and 红暴龙 (巴朵兰恩, drawn with the character's family-leader mounted art); a disabled button says why a pet cannot be ridden. Mounted art, separate mount HP, damage sharing and mounted experience follow the source. See [riding](../reverse-engineering/riding.md) and [riding evidence](../reverse-engineering/original-riding.md).
- The item shop sells the mirror accessory (镜之精灵). See [mirror accessory](mirror-accessory.md).

## Automation

- **自动练级** runs battles in place; **自动抓极品** scans encounters for high-quality pets and can run a find → capture → train cycle. Both run on the backend, keep going with no window open, can be minimized to a bar while you use other menus, and their settings are saved with the character. See [auto battle](training-helper.md) and [pet hunting](pet-hunt-helper.md).

## Toolbar and 设置

- The toolbar holds **地图导航**, **刷怪传送**, **自动练级**, **自动抓极品**, **音乐** and **设置**; it is the same on every map.
- **地图导航**: map browser with 地点 / 练级点 / Lv.1宠物 destinations; choose 步行 for portal travel or DEV 传送 for instant visits, and toggle 野外随机遇敌 there. **刷怪传送** offers verified encounter spots for levels 1–120.
- **音乐** opens the 电台 window, which also has the music switch (M) and the music volume.
- **设置** (also the classic taskbar's 系统; H opens its 操作说明): 画面 zoom (−, +, 拉到最远), 声音 (music, sound effects, music volume), 换角色, 瞬移模式 (world clicks become safe instant moves), 保存旅程, **更新日志** with the `v0.MINOR.PATCH` beta version ([versioning](../versioning/version-system.md)) and 操作说明. Volume, the music and effects switches, zoom and 瞬移模式 are remembered per device (`viewer.cfg`).
- 设置's collapsed **开发者** section holds **GM 调试**: raise levels to 120, set or add base stats, grant allocation points and special pets, recover, escape battles without rewards. See [GM controls](gm-controls.md).
- The **五人镜像队** switch is in the 自动练级 window.
- Removed: the 骑乘 dropdown (ride from the pet window), 立即遇敌, and the Samgir shortcuts 村外探险 / 返回村庄, Villager, 道具店 and 挑战强敌. Without 挑战强敌 the MVP quest's finale can no longer be started.

After re-importing maps or encounters, regenerate the tracked spot indexes with `python3 tools/build_training_spots.py` and `python3 tools/build_level_one_spots.py`.
