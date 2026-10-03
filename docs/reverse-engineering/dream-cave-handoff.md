# 梦幻洞窟前三轮交接

基线已对齐main `182d4c9`，保留`1670261`配置修复及全部已合任务/联机修复。公共时间门、四TimeMan来自foundation，不复制第二套时钟。前三轮32/33/34已交付；2026-10-03新增获授权的≥35免费光／20项可重复随机奖，详见 dream-repeat-reward-handoff.md。本次捕宠便利与通用合法到达资格是另片，不在重复奖提交中。

## 合并后完整增量导入

在仓库根、独立可写legacy目录执行；不要对symlink资源写入：

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/split_manifests.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

原敌1095/1087/1086/1096分别使用100280/100346/100343/100295；现battle/index均有完整sheet，无需额外battle art。四TimeMan双模式由quest importer导出到quests/npcs，两个模式都在map400 pack，必须执行editor import后才可用ResourceLoader渲染。

## 定向验收与证据

- Python：`test_dream_cave_source_audit.py`、`test_dream_cave_world.py`，源字段与SHA、三轮顺序、十敌七槽、原迷宫不越终战、42重复门原首对象优先。
- Godot：`dream_cave_quest_test`（成人礼真前置、三轮原迷宫与战斗/save失败/第三轮END34/读回/LAN双socket）；`dream_equipment_test`（普通字段/等级35/原耐久/存档）；`golden_bui_helper_remote_test`（未放宽旧44空键断言）。
- 390×844静音离屏生产GameScene：`dream_time_walking_ui_test`（真实踩原M门、位置先于check、930→931跨时段回退）；`dream_timeman_ui_test`（四NPC两模式/原对白真点击/碰撞不变）；`dream_cave_ui_test`（明确第三轮前置与迷宫回程fixture，真实十敌战点击、源胜Warp、第三轮交付END34）。手机fixture不替代前述Backend自然三轮。
- 日志`/private/tmp/dream-cave-test.log`、`dream-equipment.log`、`dream-golden-remote.log`、`dream-time-walking.log`、`dream-timeman-ui.log`、`dream-cave-ui.log`。PNG在`/private/tmp/dream-cave-shots`：走门2张、TimeMan对白8张及无遮挡原图8张、第三轮终战领奖4张，共22张已逐张view_image；各日志0 failures且无SCRIPT ERROR。不提交资源或截图。
- 尚未实现：BODY、魔法/抗性、原敌特殊技能、2603离线掉落/丢地消失的地面物品生命周期。普通帽/琴定义2605/2606旧0耐久迁移由foundation另片负责；新领取实例使用原耐久。

只targeted，未运行full，未操作live或真实save；不以编译或来源解析代替整链验收。
