# full185 固定守卫与野战权威回归核查

基线为 `main b2836e8`，新池槽分支 `fix/full185-guard-authority`。本片仅改测试与测试路径驱动，不修改Backend、Catalog、Party结算或arrival策略，不放宽项目瞬移资格。

## 首先实测生产行为

`/private/tmp/full185-guard-production-probe.log` 来自未修改生产代码的Backend、真实原地图与原NPC，0 failures。探针源码保存在 `/private/tmp/tmux-agents/bonus-last-cave-chains/full185-guard-probe.gd`。

- 直接 `position_changed(41,(34,42))` 后 `quest_talk` 返回 `ok:false`、`type:rejected`，reason为「项目补充：请从原入口沿原路线通过门、迷宫及守卫；项目瞬移不授予任务到达资格。」
- 从400原时间入口经真实check_passage/report_position，再逐格走原迷宫到同一格，`quest_talk` 返回真实dialogue，确认后 `ok=true / battle_open=true / enemies=10`；真实胜战close返回 `ok:true / outcome:win`。
- 未同步位置直接请求100(600,500)遇敌返回「位置已改变或尚未确认，请同步服务器位置后再遇敌。」；通过权威report_position到同一点后相同wild命令成功开战。

因此本组已定位失败没有证明c55、arrival或掉落A破坏合法生产开战；直接赋位置不再代表合法路线，野外请求参数也不再替服务器移动角色。

## 四套根因与修复边界

| 套件 | full185实际失败来源 | 本片修复／保留的目标 |
|---|---|---|
| original_fixed_guards_test | `source_talk`直接站到梦德/强恩NPC原格；5个talk因缺合法路线拒绝，LAN又直接访问不存在的dialogue字段 | 本套自身run/lan_guard改用独立fixed_guard_route：公开梦德原口令门、七图连续路；强恩复用原入口/三口令/原路线driver。新增直接项目到达确实拒绝断言。完整敌顺序与数量、savefail、原胜Warp、重复确认、两socket旧token均保留 |
| personal_quest_npcs_test | 同一旧source_talk使4个dieact0守卫无法启动；「缺道具」负例以前可能仅因缺路线而误过 | 仅本类override对107/318走现legacy_cave_route；公开hougyoku保原投影fixture。缺道具必须先成功开窗，并核对原source deniedmsg。道具扣留／原掉落、savefail、隐藏严格>300、restart、三socket同角色一致均保留 |
| original_dream_passage_test | 负例矩阵通过，但最终正例直接放到34,42，没有本次合法迷宫路线 | 终战前仅换成现dream_backend_route.guard，分别经过41/42原时间门与完整迷宫，显式核10敌。其它raw/party/receipt跨墙拒绝、原portal、胜后Warp41与同组件移动断言保持 |
| lan_party_battle_test | wild_gold请求100(600,500)，真实服务器仍在1000(81,90)，40次请求全部被权威坐标检查拒绝；随后访问空pending.enemies报错 | 先明确验证旧异位请求拒绝且RNG/pending不变，再通过真实Hub leader report同步并跟随队员，然后原wild。个人level×10金币、同troop、原slice/逃跑/死亡/共享经验/远程UI等原套件断言保留 |

公共 `source_talk` 的旧定位方法未被全局改写；它被许多测试继承。本片只新增 `guard_talk` 供fixed套件自身调用，personal在自己的类中override，避免扩大到其它owner负责的Munde测试。没有授grant或直接写scope/epoch/mark。

首次定向中的新Munde路径驱动误用无坐标后缀ID，返回「missing actual public Munde keyword gate」，已改为实际绑定 `genout/wpm_100_443_127@100:443:127`。此为测试驱动错误，不更改生产npc_by_id来兼容它。LAN拒绝时先断言并清理退出，避免二次dialogue SCRIPT ERROR掩盖第一返回。

## 验证

只运行父指定四套及先行短探针，无full、无主槽/live/save操作。各套最终通过日志及hash见外部交接文件；未新增套件，因此不用改公共suite注册列表。headless只声明行为验证，不声明像素验收。

最终受影响四套均为0 failures：

- `original_fixed_guards_test`：249秒；`personal_quest_npcs_test`：末轮通过。日志目录 `/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-6vtj2uiz`。
- `original_dream_passage_test`：85秒；`lan_party_battle_test`：220秒。日志目录 `/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-tlcbx0va`。这两套最终文件在首轮已通过，后续不重复运行。
- 首轮四套为3/4（上述新Munde驱动ID错误），末轮仅复验fixed/personal两套；不将首轮记成4/4。
