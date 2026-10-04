# 首批送物计划与验收边界

`client/server/quest_delivery_plan.gd` 是只读步骤选择器；每次从当前权威快照重新选择，不执行交易、不授予到达证明、不维护可跳步骤的私有进度。调用方通过现有 `OriginalQuests.talk/choose` 执行，并在近谈位置重核原人物、原分支与合法到达。

## 精确开放范围

| job | 原事件 | 本项终点 |
| --- | --- | --- |
| 12 | 3 | 马提交收斧头，END3 |
| 13 | 5 | 亚姆收回信，END5；必须已完成3 |
| 24 | 7 | 乌力美收花与信，END7 |
| 25 | 8 | 乌力斯凯收回信，END8；必须已完成7 |
| 5 | 37 | 卡伊特收邮件，END37 |
| 9 | 38 | 马祖给一次原随机谢礼，END38；必须已完成37 |

每次仅跑所选项；END3不代替END5，END37不代替END38。哥亚需携语言贝壳，但不额外虚构END6前置，也不自动接取或执行换宠6。马祖宝袋、切绳石补发与40级领石支线不纳入。

`select()` 返回 `step`、`done` 或带中文原因的 `manual`。只有自己的END才是done；助手因合法到达或距离隐藏的洞内步骤不能判作done。任务未开放、缺前置、委托物丢失、需卸下装备、满包、无合法洞内到达记录及未知分支均停交玩家。取消丢物任务原扣魅力，因此不能自动取消重接。

## 原分支白名单

亚姆 `sainasu/event/event03_2` index1 REQUEST / index0 ACCEPT；马提 `event03_1` index0 ACCEPT / index1 REQUEST。哥亚 `jaruga/event/event07_1` index1 REQUEST / index0 ACCEPT，`event07_3` index0 ACCEPT，`event07_2` index0 ACCEPT / index1 REQUEST。马祖 `extra/event/marju` index0 REQUEST / index1 ACCEPT，卡伊特 `extra/event/marju01` index0 REQUEST。

卡伊特分支原 `event=38`，消耗2687、给2697、写END37，不能按event字段误认成领取最终奖励。马祖最终原 `GetRandItem=2688,2689,2690` 是单次随机奖，不是玩家多选奖励，不重掷。

马祖原入口 `genout/wpm_120_19_15@120:19:15` 原样保留 `FREEWARP`、`LV>49`、`Warp=122,6,5` 与原禁组队规则，自动选择序列仅 `[yes]`。其余普通REQUEST/ACCEPT步骤为 `[yes,ok]`；白名单同时核原index、event、type、condition、actions和已审核字段，不把yes/ok当作任意菜单许可。费用、交宠、给宠、口令、服务、守卫/Boss和额外奖励选项不在本批。

源依据：`references/chenmingbiao-stone-age/gmsv/data/npc/` 下以上8个脚本；对应固定来源规格 `tools/yam_axe_quest_sources.json`、`tools/goya_deliveries_quest_sources.json`、`tools/marju_quest_sources.json`。不改写源数据或导入产物。

## 验证分层

- `quest_delivery_plan_test.gd`：明确使用状态矩阵fixture验证选择与只读性，不声称E2E；另经亚姆原对话验证savefail后计划不前移。
- `quest_delivery_marju_plan_test.gd`：独立原地图oracle，实际入口与迷宫行走确认隐藏helper步骤仍选择交信、事务保存失败不前移；包含公开位置fixture，不声称连续runner路线。
- `quest_delivery_routes_test.gd`：实际产品runner连续运行六job，逐步检查四向相邻或原portal/原FREEWARP；真正随机遇敌复用attack+compact，成功后续跑；检查原接取/原交付和保存读回。只有三链最初公共位置、等级/合法属性配置、哥亚语言贝壳是fixture，链内不project、不grant、不改flags、不固定RNG、不禁敌。
- `quest_delivery_boundaries_test.gd`：实际runner缺前置、源请求savefail、丢斧头不自动扣魅力/重发，额外选项交回手动；真实port0 WebSocket双设备停止/旧token拒绝，再从实际runner行走亚姆12并检查两端快照。额外菜单是明确的对话边界fixture，六任务本身没有新增奖励多选。

首轮80级配置曾在马祖122地图战败并按原runner停止。这是有效失败证据，不是地图连通失败。完整路线验收使用140级、437点合法配置作为既有战斗能力前置；不能据此推断50级无宠无补给人物也能无人完成。普通随机遇敌自动战斗已获用户授权；不会因此扩展守卫/Boss自动化。

## 2026-10-04 实际并集结果

产品并集使用计划原提交 `00697fdff65366ccd989ffef18f25eda3aaa1129`、执行器原提交 `9883c36d105b58754878ff757c7845c4324a133b` 和失败状态原增量 `de828a8e2924c44199d86a95e556fc3c1259a2b1`。只在pool工作树运行定向headless测试，未导入、未跑全套、未改主分支或实时存档；最终由协调者在integration分支跑全套。

| job | 实际连续移动 | 自然遇敌 | 结果 |
| --- | ---: | ---: | --- |
| 12 | 434 | 19 | END3，继续13 |
| 13 | 430 | 13 | END5，保存读回通过 |
| 24 | 400 | 16 | END7，继续25 |
| 25 | 339 | 11 | END8，保存读回通过 |
| 5 | 4597 | 62 | END37，继续9 |
| 9 | 882 | 30 | END38，保存读回通过 |

六项合计7082次真实移动、151次自然遇敌，0失败。战数是这次自然运行的观测值，测试不固定RNG或要求该固定次数。马祖明确经过 `100→120→122→118→119→121→100→1300`，其中120→122仅由原FREEWARP事务进入，119→121是原单向出口。

双设备LAN套件0失败：实际远程亚姆12共434次移动、19次自然遇敌，两个无backend客户端看到同一END3与道具状态，保存读回通过。第二设备能停止任务，旧token拒绝；缺前置、丢物、源savefail与额外选择停止通过。最初的加速LAN驱动每100轮才让网络处理，曾导致缓冲溢出；测试驱动现每步让出网络轮询并每20轮完成真实ping往返，不把溢出归为随机失败后盲重跑。

计划矩阵、独立马祖到达/计划测试及原 `quest_arrival_marju_test.gd` 均0失败。三个Python源测试模块共4项通过，使用已有 `.tools/asset-venv/bin/python`（系统Python缺Pillow，未安装新依赖）。所有这些测试都是headless，不验证渲染像素。
