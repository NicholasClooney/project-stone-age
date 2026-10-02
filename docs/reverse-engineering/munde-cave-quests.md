# 梦德洞窟：原任务9–12

开放日志“梦德洞窟”（原job8），只启用9/10/11/12。原event12其余41/42分支不导入，47百题和后期支线均不开放。固定revision、各脚本SHA与原技能槽见 `tools/munde_cave_quest_sources.json`、`bonus-cave-chains-sources.json`；共同审计中的萨顿/强恩资料是后续独立链来源，不等于本提交已激活。

## 原流程与边界

1. 等级30且已完成成人仪式，向柯尔克村姑接9；询问卡坦青年与霍特尔村姑，取得11/10委托。两人接取先后可交换。
2. 萨伊那斯(443,127)原盗贼要求精确口令“在卡坦有梦德”，进入11101(33,29)。六道原楼梯连至11107，全部来源于 `genout/11101d.create`。原返回岛屿出口保留。
3. 悟/唐分别绑定11107(22,41)/(23,41)，均挑战原527/526/528/529四敌，胜利且存档成功后传至11107(23,35)。两处旧景观免战传送已通过manifest restored_scripts移除。原borncenter1×1固定创建位置保留；不新增原游走AI。
4. 526/527分别按原10/1000概率掉2482格的枪、2483达的斧头。村庄保护石不是战斗掉落：族长同时发2419霍特尔石、2420卡坦石。
5. 首次必须卡坦先交2420，得1052铠与魅力+1，仅END11；再向霍特尔交2419，得2421勾玉并END10/12；最后向柯尔克村姑领取1357黄色大首饰，才END9并完成本日志。

助手提供九步说明、瞬移与从地图落点步行两种项目便利，不是原版功能；未开放自动执行。原战术权重、七技能槽、异常技能来源保留供审计，沿用现有战斗AI，不扩展技能系统。

奖励按原数据发放。1052身体槽尚未实现，其防御/敏捷及魔法明确未生效；1357现有护身符槽魅力+5生效，原睡眠等抗性明确未生效；2421无虚构用途。2482/2483原随机区间仍为未生效元数据，不取中值、不扩UID属性模型。统一 `OriginalItemEffects` 在背包和助手展示这些区别。

## 导入顺序

必须在独立可写资产克隆或主会话停止live后执行；不能只复制本槽缓存。恢复口令会移除旧景观入口，必须由manifest锁定11101–11107七个源地图才能维持实际地图选择。

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --sprites 100439
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100439
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
