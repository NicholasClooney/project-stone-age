# 矿工比赛27导入与验收交接

功能提交 `c6f8a8e`，公共矿石窄兼容原hash `6209e1a`（本分支等价 `6f47bbc`）。合并功能代码后，在有独立可写legacy目录的checkout运行；不要在legacy为symlink的worktree运行。协调者按主流程停止/备份/重启live，worker未操作live。

## 完整增量导入命令

从仓库根执行，使用当前本地2.5与8.0路径：

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --extra-source .tools/legacy/extracted/SA8.0-20260803 --sprites 100469
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100469
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/split_manifests.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

quest importer读取registry导入miner-contest，包括原固定战/掉落/缺表条件审计与消费票门。world须保留8.0 fallback，导入31801–31806并移除无条件scenic票门。palette统一地图纹理调色板；split/packs更新客户端资源索引，editor生成Godot纹理缓存。不提交原资源或验证截图。

## 逐敌资源证据

|enemy|template|sprite|矿工导入前状态|
|---|---|---|---|
|1040|181|100323|已有battle manifest角色及sheets/100323.png|
|1042|184|100326|已有battle/pets/100326.json及sheets/100326.png|
|1043|545|100469|原先缺失，必须执行上面的定向art导入|
|1004|544|100401|已有battle/pets/100401.json及sheets/100401.png|

100469可从原客户端完整导入；原图只有一帧，由原动画表各动作方向引用，并非项目伪造占位。`import_encounter_art.complete_actions`审核0/1/2/3/4/10动作各八方向，split生成TroopArt读取的可渲染索引。其他三只已有完整sheet，无须重复导入。不能因Session战可结算而推定自然遇敌通过TroopArt门。

## 定向验证

```sh
.tools/asset-venv/bin/python tools/test_miner_contest_quest.py
.tools/asset-venv/bin/python tools/test_miner_contest_world.py
./scripts/run.sh --headless --script res://tests/miner_contest_quest_test.gd
STONE_AGE_FOREGROUND_TEST=1 STONE_AGE_PROOF_DIR=/private/tmp/miner-contest-shots ./scripts/run.sh --position -2000,-2000 --script res://tests/miner_contest_ui_test.gd
```

原seed27固定group508的完整真实Session战保留负成长、保存失败重试与幂等检查；另以原seed27连续原权重抽组，通过Backend.wild_encounter的数据、TroopArt与Session三层门直到遇到矿石并实际结算。手机390×844测试矿石回程使用明确fixture，仅验证界面；其余比赛/领奖/消费票门为真点击。九张PNG已逐张view_image，不把headless算像素验收。不运行full。
