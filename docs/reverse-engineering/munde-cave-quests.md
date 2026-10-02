# 梦德洞窟：原任务9–12

开放日志“梦德洞窟”（原job8），只启用9/10/11/12。原event12其余41/42分支不导入，47百题和后期支线均不开放。固定revision、各脚本SHA与原技能槽见 `tools/munde_cave_quest_sources.json`、`bonus-cave-chains-sources.json`；共同审计中的萨顿/强恩资料是后续独立链来源，不等于本提交已激活。

## 原流程与边界

1. 等级30且已完成成人仪式，向柯尔克村姑接9；询问卡坦青年与霍特尔村姑，取得11/10委托。两人接取先后可交换。
2. 萨伊那斯(443,127)原盗贼要求精确口令“在卡坦有梦德”，进入11101(33,29)。六道原楼梯连至11107，全部来源于 `genout/11101d.create`。原返回岛屿出口保留。
3. 悟/唐分别绑定11107(22,41)/(23,41)，均挑战原527/526/528/529四敌，胜利且存档成功后传至11107(23,35)。两处旧景观免战传送已通过manifest restored_scripts移除。原borncenter1×1固定创建位置保留；不新增原游走AI。
4. 526/527分别按原10/1000概率掉2482格的枪、2483达的斧头。村庄保护石不是战斗掉落：族长同时发2419霍特尔石、2420卡坦石。
5. 首次必须卡坦先交2420，得1052铠与魅力+1，仅END11；再向霍特尔交2419，得2421勾玉并END10/12；最后向柯尔克村姑领取1357黄色大首饰，才END9并完成本日志。

助手提供九步说明、瞬移与从地图落点步行两种项目便利，不是原版功能；未开放自动执行。导航只允许已抵达原区域：外部只能前往入口和村庄NPC，洞内不可跳未来楼层，守卫仅当前11107入口侧可导航，族长仅战胜Warp后的同一原可走组件可导航。未解锁步骤保留说明但不给导航按钮；旧步骤、直接NPC ID与两种模式均由服务器重查。阶段键只含楼层和组件，不因同区每格移动重发任务状态，不增加原任务旗标或存档字段。原战术权重、七技能槽、异常技能来源保留供审计，沿用现有战斗AI，不扩展技能系统。

奖励按原数据发放。1052身体槽尚未实现，其防御/敏捷及魔法明确未生效；1357现有护身符槽魅力+5生效，原睡眠等抗性明确未生效；2421无虚构用途。2482/2483原随机区间仍为未生效元数据，不取中值、不扩UID属性模型。统一 `OriginalItemEffects` 在背包和助手展示这些区别。

## 导入顺序

必须在独立可写资产克隆或主会话停止live后执行；不能只复制本槽缓存。恢复口令会移除旧景观入口，必须由manifest锁定11101–11107七个源地图才能维持实际地图选择。

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --sprites 100439
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100439
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

`pack_frame_sheets`包含split，生成sprite100439的运行时JSON与sheet。四敌sprite必须依次为100432/100439/100279/100282；此前仅导任务静态NPC图会漏100439，导致battle_view少建一个演员槽。专属测试显式断言四敌图像及玩家/宠物占位共六槽，不能以战斗结算通过替代渲染验证。新增图像、导入catalog和截图均不提交Git。

## 定向验证

- `test_munde_cave_quest.py`：实际create绑定、精确事件集合与分支白名单、原交付顺序、两种概率、七地图SHA与移除景观旁路声明。
- `munde_cave_exchange_test`：独立源fixture上的每个交付保存失败回滚、首次先后关系、魅力/每个END/最终1357及重复交付。fixture放置不是路线验收。
- `munde_cave_route_test`：实际注册catalog/Session/九步helper、原口令错字/保存失败、两守卫完整四敌、固定原RNG命中两种稀有物与未命中、真实击败结算/失败重试/胜Warp、整链完成读回、双socket旧token竞争。
- `munde_cave_walking_test`：从真实口令目的地fixture起步，使用生产寻路与踩格触发，实际走完六道原楼梯，逐次核对落点并排除守卫免战旁路。此headless测试不提供像素证据。
- `munde_cave_ui_test`：独立服务器与无backend远程客户端；390×844真实离屏渲染，实际点击助手/原交付/口令按钮/装备按钮，键盘中文输入，逐图查看。岛入口从地图落点行走数百格，专门等待180秒条件期限。另在GUI测试中对楼梯踩格做坐标fixture验证，其完整行走由前述walking suite承担。

### 梦德导航独立补修

`munde_cave_navigation_test`覆盖入口前与11101–11106的原NPC/旧step双模式拒绝，11107原portal落点(18,41)归入口侧且不误锁守卫导航，原胜利点(23,35)与族长邻格(24,7)同组件并与入口侧不同；原战斗保存成功后才开放族长。真实双socket验证另一设备看到阶段变化，同组件普通report_position只发位置、不发profile/helper。交换fixture直接放置位置只验证交易，不能替代这套防绕或walking自然路线验证。

公共接点仅 `quest_helper.navigation_key`、event9的 `resolve_step`、梦德NPC的 `destination` 前置授权；组件解析与缓存全部在Munde模块，保留44与NPC-state缓存逻辑。组件排除原墙、全部NPC占位与portal；站在真实portal落点时，仅在其相邻格唯一归属一个组件时取得该组件，绝不借portal桥接两侧。

每次world导入后必须执行 `palette_images.py`：本次核验100439 sheet为P模式，但world重新写出的4749张共享图仍需恢复统一调色板（另349张已具备，0张残留RGBA）。palette处理后再plan/editor，截图不能替代调色板suite。

### 墙边邻格与实际返回落点

第二次原地图探针证实：只检查“NPC至少有一个邻格属于当前组件”不足以保证后续通用导航安全。原唐(23,41)的首个安全邻格(23,40)在族长侧，而(23,42)在入口侧；入口侧访问唐时，两种旧模式都选到了(23,40)，实证跨墙。反向从族长侧访问悟也会因首邻格(22,42)回到入口侧。探针逐一打印了24个原交互偏移的组件以及两个模式返回点，不把潜在问题冒称已复现。

独立补修 `Munde.destination` 先筛出当前组件中的NPC安全邻格，再只在该组件内洪泛寻找arrival；通用destination算法保持不变。修后入口侧唐落(23,42)，族长侧悟落(23,39)，族长near(23,6)/arrival(22,9)不变；所有允许导航均保持当前位置的组件。地图不可读、组件编号无效时拒绝，`past_guard`必须先满足胜利区域编号非负。

`munde_cave_destination_test`覆盖入口侧/族长侧×悟/唐/族长×near/arrival全部组合，调用真实Backend原NPC导航并验证实际落地位置，另验证地图失败时两个无效区域不会让族长解锁。此修复不改变已验收手机主线所用的悟入口侧和族长落点，保留既有真实图像证据。
