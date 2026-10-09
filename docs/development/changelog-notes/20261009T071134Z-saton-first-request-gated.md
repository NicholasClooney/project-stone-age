---
subject: "chore(quests): stage gated Saton first request runner"
title: "萨顿首请求运行器定向验证完成，仍未开放"
---

- 开发说明：新增默认关闭、限定A模式的萨顿job10/event13首请求运行器，沿原无收费路线调用真实REQUEST，同candidate写NOW13并分配单件2431及真实UID，随后停在手动wait_boss；不接Boss、补足迹、取消、完成奖、宠消耗或D1收费。
- 独立Start scope与萨顿call守卫保护安装、保存返回和窗口生成，只清自有登记，不借博士/44/D权限。旧返回失效即丢弃，同旧run执行标志下一tick撤除；false-after仍可能盘/cache已提交而内存按false回滚，不新增原子/重试保证。
- 九套定向测试分窗通过：萨顿guard依赖不变沿用，其余八套fresh通过。route移除旧Policy-helper真值假设，保关闭等价及错误job/event否定，独立完整expected验证真实gated prepare与Start。递归比较仅JSON来源first.cell两坐标允许有限整数int/float等值，其余键型、类型、结构及完整profile/宠UID/钱/盘/cache/serial断言保留。
- 父函数对照运行于候选环境；内部binding、GM宠/无遇敌和隔离事务/save seam便利不代表认证WS或自然验收。Session、Hub、Policy、收费writer及saton_plan未改。全部旧FAIL及盘保留，本批无stderr豁免，未注册/full/import/开gate/重启，集成验证另行进行。
