# 马祖送信与水田迷宫回报（37/38）

本批恢复送信与回报，宝袋支线未开放。任务行为取自锁定的本地
`chenmingbiao-stone-age` 快照，SHA-256 在
`tools/marju_quest_sources.json`；不是对某地区官方发行版的认证。

## 实际绑定与节点

- `extra/event/marju.create:2–12`：霍特尔1300(70,51)，马祖，实际绑定 `extra/event/marju`。
- 同 create `14–24`：水田迷宫119(97,88)，卡伊特，实际绑定 `extra/event/marju01`。
- 同 create 之后的十个宝袋绑定均不激活。未借用网页剧情，也不导入旁支奖励。
- `marju:8–18`：等级至少50、未END38，接取37并给予邮件2687；接取不完成37或38。
- `marju01:8–20`：NOW37、等级至少50、有邮件且**背包没有切绳石2697**，收邮件、给切绳石、END37。EventNo为38而完成动作写37，保留这种原始区别，不擅自改号。
- `marju:21–29`：END37、至少50级，随机给2688/2689/2690之一并END38；任务解释器按原EventNo完成位跳过已完成分支，因此不能重复领奖。
- `marju01:22–28`是MESSAGE补发切绳石；交付失败与补发失败都必须保存回滚。
- `marju01:31–38`允许未开始37且未完成37的40级角色取切绳石，**不完成37/38**。这不是绕过主链等级；若先取石后接信，原交信条件暂不成立，助手明确提示。宝袋尚未开放，可通过现有真实丢弃功能处理石头；不伪造宝袋使用结果。
- 本地日志原名：id5/event37「马祖任务」，id9/event38「水田迷宫」。38才是转生加点表中的完成节点。

## 原入口与导航边界

`genout/meiro.create` 最后一块实际绑定房子主人120(19,15)，脚本
`genout/wpm_120_19_15`：`WARP:122,6,5`、`FREE:LV>49`、`MONEY:-1`。
入口必须至少50级，并且不能组队；不是付费绕过低等级。原C
`npc_warpman.c:228–231,397–400,413–416,560–566`核查组队状态，
`302–310`将负MONEY转为不可支付分支。后端确认时重查，不接受客户端地图或队伍断言。

普通路线来自同 create：100(549,637/638)→120→入口NPC→122→118→119。
119(103,93)→121→100为出口；121没有返回119的反向传送。
五张地图逐一固定二进制SHA，不能只因地图资源存在就宣称入口恢复。
助手能导航到入口，进入122/118/119之后才能导航到卡伊特；后端同时拒绝
外部的旧步骤与伪造raw npc_id访问。按地图区域变化刷新助手，不逐格发布。
助手导航仍是项目便利，不是原版自动跑任务。

## 原装备列与效果范围

原始 `gmsv/data/itemset.txt` 实际行如下。以下列号均为零基：
19类型、22等级、31/32耐久、37–42攻防敏最小/最大、49/50魅力、55/56/57魔法参数。

| 行 / ID | 原物品 | 等级 / 槽 | 普通属性 | 魔法原字段55/56/57 |
|---|---|---|---|---|
| 2210 / 2688 | 马祖的斧头 | 50 / arm | 攻+50、防−20、敏−20 | 12 / 100 / 16（滋润Lv3） |
| 2211 / 2689 | 马祖的矛 | 50 / arm | 攻+45、敏−10、魅+4 | 2 / 100 / 11（治愈Lv3） |
| 2212 / 2690 | 马祖的棍棒 | 50 / arm | 攻+35 | 22 / 100 / 40（恩惠Lv3） |

三件耐久均2500000；六种异常抗性列63–74皆0，不能凭武器名字捏造抗性。
普通攻防敏魅使用已有装备系统并实际生效；魔法保留带来源的标签，UI注明未生效。
不扩充装备槽、存档格式或战斗效果系统。2687邮件与2697切绳石使用原图标、原描述；
切绳石补充说明宝袋尚未开放。

本主链没有NPCEnemy固定守卫，不伪造Boss或为送信增加战斗。
迷宫普通随机遭遇沿用既有敌源；本批不宣称恢复它们的原AI。

## 验证口径

专属源测试核实际create、原分支顺序/条件、37/38区别、随机物品集合、普通与魔法列、源SHA与地图SHA。
后台装备测试使用真实升级/加点/装备与存档重载。低基础防敏会触发现有属性下限，
因此差值验证先用真实分配属性点提高基础值，不修改装备公式或把下限当原数据错误。
已通过 `marju_quest_test` 的真实原入口、请求/交付/回报保存失败原子回滚、
重复令牌拒绝、原40/49/50级条件及两个真实socket一致性；进入迷宫更新双方助手，
同区域位置报告不增加广播。`marju_route_test` 使用原地图碰撞和门户验证完整连通路线。
`marju_equipment_test` 对三种武器逐件验证等级、实际普通属性、真实战斗磨损、UID与耐久存档；
公共effects与44助手/remote定向回归通过，没有运行full。

`marju_ui_test` 在实际390×844 OpenGL渲染中真实点击助手、原对话、背包滚轮与装备按钮，
完整走过接信→原入口→交信→回报→奖励详情→装备，共7图均人工逐图查看。
测试通过GM设置50级，关闭无关随机遭遇；它验证任务交互与渲染，不认证自然练级过程。
长迷宫导航等待基于对话出现条件，300秒仅为失败上限。截图保存在本机
`/private/tmp/bonus-third-marju-proof`，不提交仓库。

复现：
```sh
PYTHONPATH=tools .tools/asset-venv/bin/python -m unittest tools/test_marju_quest.py
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
STONE_AGE_TEST_JOBS=2 ./scripts/test-all.sh --only marju_equipment_test,marju_quest_test,marju_route_test
STONE_AGE_FOREGROUND_TEST=1 STONE_AGE_PROOF_DIR=/private/tmp/bonus-third-marju-proof ./scripts/run.sh --rendering-method gl_compatibility --script res://tests/marju_ui_test.gd
```
