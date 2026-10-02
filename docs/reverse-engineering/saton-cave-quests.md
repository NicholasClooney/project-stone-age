# 萨顿家宝13与补充14

本模块仅启用13、14；源revision `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`，逐文件SHA和实际绑定在 `tools/saton_cave_quest_sources.json`。原敌战术权重、七技能槽、异常技函数/参数/原行号继续见 `bonus-cave-chains-sources.json`，使用现有AI，不扩魔法或复活系统。

## 原流程与绑定

- 老人萨顿 `sainasu/event/event13_1` 实际在1112（16,15），要求等级16以上，接NOW13并给2431「盗贼们的足迹」。丢弃后原MESSAGE分支在打开对话时补发；不是等玩家按确认才发。
- 原入口为南岛100（132,421）→10701（76,67）。原楼梯连接10701–10705，第三/四层保留两条原通道，不造新门。五份原地图均锁SHA；三守卫脚本列入restored_scripts，不以旧景观传送代替。
- 三个NPCEnemy实际绑定来自100/sb_nusu.create/.template，固定中心和敌队如下。移动框保留源元数据，现实现只生成原1×1固定中心，不宣称恢复原游走。

| 脚本 | 原位置 | 敌队顺序 | 原必掉家宝 | 图像顺序 |
| --- | --- | --- | --- | --- |
| 100/sb_nusu1.arg | 10701（23,51） | 513,516 | 2428，1000/1000 | 100405,100327 |
| 100/sb_nusu2.arg | 10703（6,63） | 514,518 | 2429，1000/1000 | 100436,100340 |
| 100/sb_nusu3.arg | 10705（44,41） | 515,519 | 2430，1000/1000 | 100230,100274 |

原三守卫均需2431，dieact0、time300，未声明steal，不偷走足迹；各自宠物无固定家宝掉落。原create的name字段含私用区乱码（行10/21/32），来源原样保留，助手以中文任务动作说明，不伪称这些原名字已修复。

带回三宝：原branch0扣2428/2429/2430/2431、给2450、END13。2450原作用是复活至500，当前仅保留metadata并在库存/助手标未生效，不存在运行时复活。

## 用户授权补充与原版重复

独立supplements追加END14，并保留原source_actions/source_texts/SHA，标“补充·依据编号登记”。这不是声称原脚本写14。

青年 `sainasu/event/event13_2` 在1100（86,99），原CLEAN13分支按用户决定启用：**原版行为：可重复**。项目额外确认文案：“清除萨顿任务完成标记，可重新接取并领奖；加点项14保留，是否继续？”取消不改变任何存档字段；确认只清13，不清14、不扣已有秘药。经原server token及候选事务处理，不允许客户端改旗标。再次实际收集三宝并交付会获得第二份2450。

原死后隐藏是全服共享，本项目按角色各自计算。个人保存成功后才隐藏，严格超过300秒恢复，其他角色不隐藏；服务器重启复位，不新增存档字段。两设备共享同一角色状态。保存失败保留守卫和原待结算结果，重试不重掷掉落、不重复领取。

## 助手边界

助手瞬移属于项目便利。洞内仅当前楼层、当前连通区域可以导航，最终near/arrival目标同区；未知区域/地图失败关闭。原传送落点只在唯一相邻区域时可识别。所有墙、活动NPC及传送格从区域洪泛排除。阶段key仅10701–10705命名，保留其他任务key与个人NPC状态版本。直接npc_id和旧step都重查当前权威位置。青年CLEAN步骤由公共restart_steps生成，独立Saton.can_visit也允许其原村庄目标，避免把公共追加的重做步骤误锁。

## 导入与验收

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --sprites 100405
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100405
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

pack包含split。须保留前置Jan已导入的100436；main未导入该前置时同时补导。world重写共享图像后palette不可省，不能依赖代理槽资源。

- `tools/test_saton_cave_quest.py`：精确5NPC/13和14/源三队与概率/五图SHA/原CLEAN及补充差异。
- `saton_cave_exchange_test`：REQUEST、丢失补领MESSAGE、三宝交付、每步失败回滚；确认/取消/旧token/清13留14、重复2450、两设备；三宝是明示交易fixture。
- `saton_cave_route_test`：实际原三队战斗、固定seed的原必掉三宝、失败存档不隐藏不发物、结算重试、300/301、独立角色、13/14读回；战斗开始位置是明示NPC fixture，不冒充自然步行。
- `saton_cave_navigation_test`：全部原落点、两mode最终点同component、旧step/rawNPC跨层拒绝、地图失败关闭；同角色两socket保存失败/隐藏/300边界；真实Hub三socket验证另一角色守卫与掉落独立。
- `saton_cave_walking_test`：从原入口落点起，生产移动连续走四段原楼梯并到达三处守卫邻格。
- `saton_cave_ui_test`：390×844实际remote GameScene、六场原两敌战斗和完整两轮领奖、守卫隐藏/300/301恢复、库存未实现复活提示、原青年清除确认的取消与确认，所有操作通过真实按钮/网络；楼梯采用原格触发fixture，完整连接步行由独立suite覆盖。截图逐张查看，不提交。

仅定向验证，无full；不触碰真实存档或主线运行服务。
