# 原版任务解释器与已知偏差

已开放 `sainasu/event/event02_1`、`event02_2` 的不可思议的贝壳任务。
公开目录 `client/data/early-quests.json` 启用事件 2。玩家可点击日美子
（萨姆吉尔 1000，57/124）与弥生（玛丽娜丝 2000，55/92）。
测试使用真实 QuestCatalog 和原分支，不伪造对白或奖励。
伐木扩展按地图与数据、战斗掉物、完整事件链分别提交；仅启用目录中的事件才公开 NPC。

原参考 `gmsv/npc/npc_exchangeman.c` 保留文件分支顺序，EventNo 正数且
ENDEV 已置位时跳过该分支。EVENT 逗号为 OR、`&` 为 AND。解释器只支持
本期所需 LV、SP、ITEM、NOWEV、ENDEV，其他谓词/动作失败关闭。
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

## 导入格式与资源

`tools/early_quest_sources.json` 固定 NPC 参数、create、itemset、jobdaily
的来源及 SHA256。`tools/import_early_quests.py` 按 GB18030 解码并校验，
生成忽略提交的 `client/assets/legacy/quests/catalog.json`，目录 version=1。
`npcs` 保存原地图、cell、贴图及有序 branches；branch 保存 EventNo、TYPE、
EVENT、原文消息与动作。`items` 按原 ID 保存 name/memo/icon，`jobs` 保存
jobdaily 标题与 NOWEV/ENDEV 状态。新增来源需更新白名单，未知语法拒绝导入。

物品 2414（不可思议的贝壳）、2415（仙尼亚的花）与两个静态 NPC 均使用
2.5 原图。网页目录和物品归 core，NPC 图归各自地图包。导入任务后运行
`tools/plan_web_packs.py` 与 headless editor import，无需重导世界或遇敌。
Headless 测试不验证渲染像素。

## 伐木原地图与数据准备

哈恩的锻冶场 20508 使用原 `jyaruga/dungeon/dan_2-05-08`，25×25。
20501(8,53) 原入口到 20508(7,24)，两格原返回门均回原入口；
20508(20,11) 到 200(396,821) 为原单向出口，没有补造反向门。
原重复入口到 (8,24) 保留审查记录，采用先列出的 (7,24)。
全 70 图块、60 物件均可用 2.5 图形，哈恩 (12,11) 邻格从入口可达。

完整目录含贝壳 2 NPC 与伐木 5 NPC、12 件原道具。NPC 与 branch 的 `events`
记录审核链关联，EventNo 原值保留，不能用正数 EventNo 筛掉科巴尔特、赛尚等
无自身事件号的分支。哈恩 1837/1838 钥匙旁支 `enabled=false`，不公开。
原 jobdaily 只有 event2、event18 标题，event19 不捏造日志标题。
