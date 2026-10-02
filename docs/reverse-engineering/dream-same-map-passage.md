# 梦幻洞窟同图移动的服务器边界

## 问题与修复

原时间门检查在`origin==target`时允许移动。因此角色已在41/42战前房间时，可以从宠物大全选择呼拔拔72或卡比特111的普通遇敌点(34,35)，通过同图`report_position`进入终战后领奖区；普通快捷移动有相同问题。任务助手自己的组件筛选不能覆盖这些入口。

`Backend._cmd_report_position`现在先调用独立`original_dream_passage.gd`，再处理`quest_auto.accept_report`。只约束41/42的同图位置报告，不增加新的捕宠旅行许可，也不改变其他任务门。

1. 地图目录、物理地图、坐标和组件必须可核验；两个未知组件编号不能互等放行。整数与JSON浮点整数按同一坐标比较，分数和畸形坐标拒绝。
2. 复用`Dream.region`的原地图组件，排除两终战守卫和仙人占格。同一已知组件内移动允许。
3. 跨组件仅允许角色**服务器当前位置**正是已启用原portal格，且原目标地图、目标坐标完全一致；若有时段条件仍用公共服务器时钟。知道某个落点、站在任意portal或传入自称party的字段都不构成权限。
4. 拒绝时保持权威位置和奖励状态，广播服务器原位置，修复远程客户端的先行显示。此前已签发的helper回执也先经过组件检查，不能用于跨墙。

原固定战胜利仍由服务器结算执行原Warp；没有新增客户端通行证或合成任务旗标。41和42战胜后原目标都为41(34,39)，领奖组件内后续移动允许。

## 组队与其他公共调用

没有修改stationary、任务助手key、party settlement或时间门。`_following_party`仅由内部`Backend.report_party_position`设置，客户端命令分派不会调用这个无`_cmd_`前缀的方法，也不会读取客户端的同名字段。

实际来源是`ProfileHub.handle`保存队长操作前位置，处理其命令，再调用`_party_follow`。`Party.follow`先验证队长，且前后位置相同立即返回空数组；因此被拒绝的队长跳墙不会给队员发内部移动。合法原portal移动后，队员由这条现有内部路径跟随，不要求队员此前也站在同一个portal格。测试覆盖真实Hub组队、非法队长位置保持、合法原warp带队及外部伪造party字段。

这不是对任意同图跨组件的一律拒绝：原迷宫portal、同区走动、胜战Warp和由合法队长移动产生的跟随均保留。测试驱动也验证原arrival_lock需要先真实走离、再踩回同一portal的路线。

## 定向验证

- `original_dream_passage_test`：真实Backend、41/42的战前→领奖拒绝、位置/奖励/旗标不变、原portal精确源与目标、同区移动、旧有效receipt、缺目录/缺物理地图/未知组件/畸形坐标、两张图的真实十敌胜战Warp、真实Hub组队、双socket。
- `dream_catch_boundary_test`：真实远程GameScene在41和42点击宠物大全的实际“瞬移去抓”按钮，观测服务器确实收到(34,35)且拒绝，客户端退回(47,54)，无奖励变化或找宠启动；关闭面板后再用生产blink_to快捷移动核验同一拒绝和回退。headless验证交互和协议，不声称像素验收。
- `dream_cave_quest_test`：既有三轮真实交易、迷宫与终战链。
- `original_time_passage_test`、`dream_time_walking_ui_test`：原时段、跨相位拒绝、真实走门与组队；本次headless不新增截图结论。
- `stationary_encounters_test`：保留原地遇敌行为。
- `lv1_hunt_navigation_test`：139条原地点断言保留；柏克尔先经原M门和四段迷宫portal再选目标启动权威找宠。相邻路点驱动只调用生产walk_to，不直接设置game.path，不宣称已实现整迷宫自动寻路。

本批不运行full。A/B捕宠便利策略仍待用户裁定；不开放跨梦幻时间入口、不新增矿山票门便利。历史完整目标盘点见[gated-pet-navigation-audit.md](gated-pet-navigation-audit.md)，其中“同图放行”是4854c86修复前状态；其他任务门目前未统一拦截的限制仍成立。
