# 原版任务解释器与已知偏差

本期只支持 `sainasu/event/event02_1`、`event02_2` 的不可思议的贝壳任务。
共享机制默认通过 `client/data/early-quests.json` 关闭公开事件；测试只在真实
QuestCatalog 实例中覆盖 `enabled_events=[2]`，不伪造分支或奖励。
伐木依赖缺失地图 20508、event19、许可证门控木敌群及战斗掉物，尚未实现。

原参考 `gmsv/npc/npc_exchangeman.c` 保留文件分支顺序，EventNo 正数且
ENDEV 已置位时跳过该分支。EVENT 逗号为 OR、`&` 为 AND。解释器只支持
本期所需 LV、SP、ITEM、NOWEV、ENDEV，其他谓词/动作失败关闭。MESSAGE 虽可由来源目录表示，本期解释器不执行；贝壳没有此分支，不能据此声称伐木补物消息可用。
SP 来自原 CHAR_SAVEPOINT 累积位集合，不能把当前地图当出生村。
新角色与旧 prototype 存档明确默认萨姆吉尔初始位 0，origin 标注
`prototype_default`，不冒充原版出生数据导入。

REQUEST YES 成功交换后才置 NOW，已 NOW 的 REQUEST 进入 StopMsg；
取消删除 GetItem 裸 ID 的所有实例，清 NOW，魅力大于零扣一。
ACCEPT 按 `_NEWEVENT` 流程先 YES 展示 ThanksMsg，再 OK 才交换并 END。
CLEAN YES 清指定 NOW/END，NO 和窗口关闭不改变存档。
服务器重验分支与活动/距离；只接受服务器 token，不接受客户端奖励或 flags。

与参考源码的有意差异：NOW 清除使用 AND NOT，修正原 XOR 非幂等缺陷；
带 `*n` 的删除按脚本意图消费 n 件，而非复制参考 C 空实现；确认保持服务器
选定分支并重验，避免原回调从头选分支造成的并发漏洞。15 格交换容量按
先删后给的净结果验证，不复制 C 循环索引复用和 REQUEST 二次预检缺陷。
旧 prototype 物品仍保留一键一格的计数堆叠，原版新物品一实例一格，装备副本
不占普通背包；旧存档超容量不截断，但拒绝继续领取超容量奖励。

任务提交同步存档；写入失败恢复完整交易前 profile，不广播成功 profile。
原服务器 NOW/END 六个 32 位字持久化到 v5 存档；事件清除与迁移可重复。
存档点原位证据见 `char/char_data.c:689-720`、`npc_savepoint.c:543-551`；
确认流程见 `npc_exchangeman.c:570-601,1744-1768`，距离见
`npcutil.c:553-567`，旗标见 `npcutil.c:1310-1422`。
