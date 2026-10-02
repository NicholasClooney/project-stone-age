# 龙洞三玉入口公共接口

原绑定 `genout/20800npc.create` → 20807(11,37) `genout/wpm_20807_11_37`，声明 `handlers["genout/wpm_20807_11_37"]={"kind":"warpman","events":[17]}`，同时锁定两源SHA、将create列入模块creates、三枚2457/2458/2459列入items。

严格接纳原 `FREE:ITEM=2457&ITEM=2458&ITEM=2459`、`MONEY:-1`、`WARP:20807,13,35` 及四原消息字段；不允许改条件、目标或增加DelItem。原 `npc_eventaction.c:1243–1280,1423–1424,1524–1538` 逐项检查背包；脚本没有DelItem，因此只验三玉，不消费。`npc_warpman.c:228–231,393–400,560–566` 开窗/确认均禁止组队，沿原PartyMsg。

复用 FREEWARP 的服务器候选profile保存事务和令牌：逐项少一枚拒绝；开窗后失去物品或加入队伍拒绝；取消及保存失败不移动；保存成功移动到20807(13,35)，三UID不变；重复确认拒绝。测试实际原地图metadata、真实读回与三socket同角色/队伍变化通过。没有开放新自动任务，不修改helper；任务模块须恢复此scenic脚本、去除无条件旁路并验收完整原路线。
