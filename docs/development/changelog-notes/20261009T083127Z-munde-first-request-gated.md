---
subject: "chore(quests): stage gated Munde first request runner"
title: "梦德首请求运行器定向验证完成，仍未开放"
---

- 开发说明：新增独立默认关闭、A模式的梦德job8/event9首请求运行器，保原LV>29且END4条件，沿原无收费路线执行空动作REQUEST，仅写NOW9后转手动；不接11/10、口令/Warp、Charm、Boss、奖励、宠消耗或D1。
- 独立Start与call身份守卫保护安装、保存返回及窗口生成，只撤自有登记，不借博士/萨顿/44/D权限；旧同run执行标志下一tick撤，false-after仍可能盘/cache已提交而内存回滚，不新增hold或原子/重试保证。Session、Hub、Policy、收费writer及munde_plan未改。
- 八套定向测试在同一fresh窗16阶段通过，无stderr豁免。真实路线无准入/selector替身；完整expected、严格native首差异、token关联/serial/replay与全profile/钱/物品/宠UID/三盘/cache保留。proposal坐标是int literal，无数值跨型例外；原manifest限定字段核有限整数，真实load另核完整JSON持久边界。
- LV30/END4/无遇敌、内部binding、GM宠及save seam属于测试便利，不代表自然资格、认证WS或Session内部物理故障；父函数对照运行于候选环境，动态隔离只验证Munde至博士/萨顿方向。历史FAIL与盘保留；未注册/full/import/开gate/重启，集成验证另行进行。
