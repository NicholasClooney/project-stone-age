# 自动任务第二批：暂停交接（2026-10-06）

用户决定第二批收尾并暂停。本页记录 main 上已有什么、什么还关着、剩下多少工作，以及接手要看的文件。总决定见 [ideas.md](ideas.md) 的「全任务自动化」条目。

## 玩家现在能用的

这些在暂停前已上线，未受本次合并影响：

- 首批送物：亚姆 3/5、哥亚 7/8、马祖 37/38，以及旧三项（药草、贝壳、成人）全程原路。
- 移动三模式 A/B/C。B/C 只用于 36 条审核公开走廊；保护段和未审核的公开段都按 A 走。
- 44 金布伊自动：按原题库作答，猜拳原随机；需要玩家已有票。
- 奖励多选等玩家选完自动续跑；Boss 停下交玩家，打赢后按继续。

## 本次合并进 main 但对玩家关闭的

合并来源：`integrate/batch2`（试集成 `trial/batch2` 67839fba，加 7 片收尾和 3 个回归修复），全量测试 571/571 全绿后合主。

| 功能 | 关闭位置 | 开放时要做的 |
|---|---|---|
| 限时刷物（计时账本、预算、续跑、checkpoint、周期进度） | `client/server/backend.gd` `QUEST_LOOT_PUBLIC_ENABLED := false`；客户端只在服务器能力 `quest_loot_enabled` 为 true 时显示预算面板 | 先补 P3 和 2760 掉落验收，再改成 true，跑全量测试 |
| 实体通行证（原 2422 道具） | `client/server/game_session.gd` `ENTITY_TRAVEL_PASS_ENABLED := false`；买证仍是旧的 200 永久通行资格 | 先定旧资格怎么兼容，再接原道具店 |
| 入口失败回退寻路（Nav/Entry） | 入口实例默认关，回退首行不搜索（075895） | 修好大图预算后再开 |
| 收费原子交易（200 证、300 赛姆过路费） | 交易代码已在；自动任务的运行器付款桥没有接线，自动任务遇到收费仍停下交玩家 | 做运行器付款桥（running 下 F1 入口冲突，核心只有设计稿） |
| 常规链纯计划（萨顿/博士/哈恩/梦德/强恩/五兄弟/龙洞/矿工） | `quest_auto` 的 Policy 白名单和 Registry 没有这些 job；只有测试调用 | 逐条做真实执行，再加进白名单 |
| 片7 四精灵/漆黑纯计划 | 同上，只有测试调用；地入口仍关、风41 守卫到达仍手动 | 同上 |

存档格式：存档版本从 7 升到 8（刷物账本）。旧档 1–7 加载时补空账本，有迁移测试；v8 缺账本或账本损坏会拒绝。合主前已备份存档。

## 剩下的工作（约 6.5–12 SP）

| 工作线 | 已做 | 还剩 | SP |
|---|---|---|---|
| 刷物（核心/UI） | A0–P2、两场战斗、checkpoint、周期进度、开关隔离；2760 自然试跑完整跑通但没掉落（313 s，325 次尝试/13 场，2760 收 0） | P3 定时心跳（诊断失败，UNPROVEN，未提交）；2760 自然掉落验收；2764 领石前置的自然路线；开放入口 | 0.4–0.8 |
| 常规链 片6 | 七套纯计划 1538 断言；吉德、成人首段、强恩首花真实交易 | 每条链真实执行；哈恩大图寻路预算；20804 原遇敌池少一组 1212:10（只读排查中） | 2.4–4.4 |
| 30 借镜、34/35 只引导 | 未开始 | 全部 | 0.4–0.8 |
| 片7 四精灵 + 漆黑到王前 | 纯计划 + 火之精灵源数据分层；付费路线接线稿 | 运行器付费桥、交通；下一道门真实路线 3 次失败（寻路预算）；各段真实执行 | 2.2–4.2 |
| 44 首票自动买 | 合同和静态稿 | 按①（大厅直接买）实现 | 0.2–0.4 |
| 片8 可选任务（金羊第二段、四精灵袋/箱/献宠、END6） | 未开始 | 全部 | 1.5–2.9 |
| 红龙骑乘换色 C | 1974 份草稿，完整审核 0 | 全套 4416 张审核；脚边/翼根仍有未定像素 | 未估（约 1–2） |

## 已定决定

- 移动：A 正常走路（默认）、B 一步到位、C 快速前进（每跳最多 3 格、约 2 倍速、逐格原版遇敌；参数是默认值，用户看过再调）。保护段永远逐格走，传送不授予合法到达。
- 普通战自动打（attack + compact）；Boss 停下交玩家；奖励多选等玩家选完自动续跑。
- 答题、口令按原数据自动作答；猜拳原随机，只做合法重试。
- 刷物按时间封顶，每步默认 30 分钟，可调 1–180。
- 必需费用自动付（用户选 B）：通行证 200、赛姆过路费 300，以及 44 第一张入场票。额外/可选消费仍手动。清单见 ideas.md。
- 44 首票：用户已定①（2026-10-07）：开始 44 自动时若无票且钱够，在大厅按原价自动买一张（项目便利）；夜间临时的②作废。
- 金羊拆两段可选任务；四精灵袋/箱/献宠、哥亚 END6 换宠都是单独可选任务。
- 精灵王最终确认永远手动。

## 接手文件

这些交接写在 `/private/tmp`，重启后可能被清掉。

- 总清单（试集成 64 片）：`/private/tmp/tmux-agents/codex-projects-stone-age-1/trial-integration-ordered-manifest.md`
- 收尾 7 片：`/private/tmp/tmux-agents/codex-projects-stone-age-1/batch2-final-append-manifest.md`
- 刷物核心：`/private/tmp/tmux-agents/quest-auto-v2-core/loot-final-handoff/handoff.md`，2760 试跑报告在 `final-2760-p3-ready/` 下
- 收费：`/private/tmp/tmux-agents/quest-auto-v2-core/mainline-fees-commit/handoff.md`、`/private/tmp/tmux-agents/quest-auto-v2-ui/mainline-fees-ui-commit/handoff.md`、费用清单 `/private/tmp/tmux-agents/quest-auto-v2-navigation/regular-chains/paid-required/fee-inventory.md`
- 44 首票合同稿：`/private/tmp/tmux-agents/quest-auto-v2-core/golden44-first-ticket-contract/`（2026-10-07 重启后已丢失）
- 导航（常规链）：`/private/tmp/tmux-agents/quest-auto-v2-navigation/final-pause-handoff.md`
- 片7：`/private/tmp/tmux-agents/codex-projects-stone-age-quest-auto-v2-piece7/final-pause-handoff/handoff.md`
- 第二批规划与 SP：`/private/tmp/tmux-agents/quest-auto-batch-two-plan/report.md`

## 未合主的分支和存档

- 红龙：分支 `feat/red-dragon-riding-recolor`（HEAD a835ff8f，pool-d）。不合主：会给仓库多加约 55 MiB 的审图记录。
  - 临时证据约 667 MiB，已打包到 `build/archive/red-dragon-recolor-evidence-2026-10-05.tar.gz`（458 MB，不进 git）。
  - 归档说明：`/private/tmp/tmux-agents/codex-projects-stone-age-1/batch2-red-draft-archive.md`。
- 未提交的 tmp 稿（P3 心跳、44 首票、运行器付费桥、哈恩 WIP、领石 ae231）：留在各负责人的 pool 槽，各交接里写了路径。
- pool 槽：pool-a 到 pool-g 仍被各负责人租着，没有释放；分支和失败现场都保留。

## 重启时

- 第二批用完了一个 Codex 账号的额度（约 1.5 天）。建议同时只开核心、UI、导航三个负责人，Codex 主面板每 1–2 小时批审一次。
- 44 首票：用户已定①（2026-10-07）：开始 44 自动时若无票且钱够，在大厅按原价自动买一张（项目便利）；夜间临时的②作废。
- 第一件事：刷物 P3 和 2760 掉落验收，然后打开 `QUEST_LOOT_PUBLIC_ENABLED`，跑全量测试上线。

## 2026-10-07 重启后续合主

- main 快进到 `e2c58ca9`：合入核心 pool-j 已提交部分（P3、公开入口、收费生命周期底座到 `1f344dc4`）、UI pool-i（公开刷物 UI、认证隔离、自然退休）、导航 pool-b（梦德到首 Boss 前、萨顿和博士首请求），外加 UI 修复 `626b403f` 和受控 P3 取消测试 `1bd08227`。全量测试 586/587，所有开关仍然关闭。
- 测试注册：常规全量改跑 `quest_auto_loot_heartbeat_controlled_cancel_test`。原随机的 `quest_auto_loot_heartbeat_cancel_test` 移出全量，作为自然场景的有限验收，和 2760 自然试跑一样单独跑。它的随机失败没有被修复。
- 已知偶发：`quest_catalog_source_test` 在负载下偶尔失败，单跑 3/3 通过。原因是 main 原有的不确定性：快照里 `npc_by_id` 会刷新 NPC 出生，出生失败后每真实 1 秒随机重试；不是本批引入的。后续做只改测试的确定性出生 fixture。
- 旧槽 a/c/e/f/g/h 已释放，各自没提交的工作保存在 `wip/pool-<x>-20261007` 分支。
- Stop v3 候选仍在 pool-j，未提交。已知缺口：W1 写入成功、W2 失败之后再按 Stop，会一直无法退役。
