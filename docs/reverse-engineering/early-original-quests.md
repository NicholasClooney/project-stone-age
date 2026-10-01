# 原版任务解释器与已知偏差

已开放 `sainasu/event/event02_1`、`event02_2` 的不可思议的贝壳任务。
公开目录 `client/data/early-quests.json` 启用事件 1、2、4、18、19。玩家可点击日美子
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

完整目录含贝壳 2 NPC、伐木 5 NPC 与药草 2 NPC、14 件原道具。NPC 与 branch 的 `events`
记录审核链关联，EventNo 原值保留，不能用正数 EventNo 筛掉科巴尔特、赛尚等
无自身事件号的分支。哈恩 1837/1838 钥匙旁支 `enabled=false`，不公开。
当前导入的原 jobdaily 有 event1、event2、event18 标题，event19 不捏造日志标题。

## 已开放伐木链

15级起在霍特尔村 3300(60,75) 找巴尔接委托书2466；到锻冶场20508(12,11)
找哈恩接 event19 领空壶2463；阿鲁姆洞窟20507(32,29) 科巴尔特换满壶2464；
哈恩收壶及委托书制斧2465，巴尔收斧给推荐书2467与断斧2484。
赛尚在加加村3000(114,69) 收推荐书发许可证2478，持证按原遇敌表采木，
收回许可证及木材，依0–14档给石币，14档另给杉的手环2481。
12档不删除推荐书是原文件例外，保留原条件与删除列表。

八卦年轻人3300(46,55) CLEAN18、哈恩 CLEAN19 可重新接链；断斧可交哈恩
换改造斧2485。两种斧和手环当前只显示/持有，原装备属性尚未实现。
MESSAGE 打开即按原分支交换并同步保存后显示原 NomalWindowMsg；取消请求
删全部赠物副本。木链 REQUEST 保留原交换前实际空格预检，贝壳维持既有净容量
兼容规则。所有原交易先候选验证后一次提交，失败恢复 profile。

GetStone 使用 `player.gold`；原 `_FIX_MAX_GOLD` 启用，未转生上限1000000，
达到或超过整笔拒绝，不截断奖励、不删除输入。原上限公式还含转生次数，
目前无转生系统，不假装复现该扩展。数据依据 `char_base.c:2668–2678`、
`npc_exchangeman.c:2584–2595`。采木与组队/恢复范围见
[木材掉落](original-wood-drops.md)。

## 已开放药草（event1 / job30）

原 `jaruga/event/event.create:4–25`：村庄小姑娘在塔姆塔姆村3110(16,15)，
graphic16065/dir6；咍罗山的医生在山顶20105(16,20)，graphic16024/dir6。
共享 create 的成人礼两个 NPC 本轮已另行核查后开放，证据见下节。
`event01_1` 的 REQUEST 仅要求 LV>0，无 SP 限制，置 NOW1；医生 NOW1
且无2401给哈罗的香草2401；小姑娘 NOW1&ITEM=2401 收药给2427并置 END1。
jobdaily 原标题为「塔姆塔姆村的药草」。无 CLEAN，完成后不重做；进行中丢药
可向医生补领。取消沿原 REQUEST 行为扣魅力一，GetItem 为空不另删药。

医生 ITEM1984 提示与1982/1983磨药分支保留完整来源但 disabled；取药分支
原条件含 NOW87/END87，保留于 `source_condition` 和 `disabled_conditions`，
有效 `condition` 只选原 NOW1 子句，不导出或激活 event87。编号 AcceptMsg1/2、
ThanksMsg1..4 按序合并成完整原对白；兼容 NomalMsg 与 NomalWindowMsg。
交易在最后 OK 才提交，满包取药拒绝，满包交药按净容量交换，保存失败回滚。

物品2401使用2.5 logical icon23030；2427使用22002。NPC图各归map3110/map20105，
目录与物品图归core。现有两图及原门已导入，无需重导世界或遇敌；测试验证
near/arrival 安全落点与真实导航网格可达，远程无 backend 客户端按原按钮交付。
香草的原 ITEM_useRecovery 体100和护身符装备属性仅保存原道具说明，功能尚未实现。
药草助手只提供三步导航；自动执行支持贝壳与成人仪式。


## 已开放成人仪式（event4 / job1）

`jaruga/event/event.create:28–50`：审判 map10204(14,6)，graphic16001/dir4；
差使(188,13)，graphic16203/dir4。event04_1 SHA256
`fcba69368d1f849cb8a22dbc5e1503ca89515698424f7f710844197a353ec570`，
event04_2 SHA256 `5b4bea387c16efa89d72072e82fa1e3fb4c071d8606767c8b33c08481832992b`。
审判 REQUEST 的条件为 LV>0；差使 NOW4&ITEM!=2417，直接发2417*15，需十五个
独立空格。仪玉不是战斗掉落。审判 ITEM=2417*15 收十五玉、发2418并 END4。
无 CLEAN；丢失部分仪玉而仍持玉时原差使不会补足，助手明确保留原拒绝条件。
2418 的原装备等级是30；本提交恢复持有、交付和丢弃，尚不实现装备效果。

正常入口另外有原等级条件，纠正早先把30仅解释为入口台词的核查结论：
`genout/event04n.create` SHA `eb6715d3c5aeabdd1467f44d1f1bf32d570039c29ece4604e182538e0540b1a9`
将仪的值班者置于10202(31,13)，graphic16207/dir5；其脚本
`genout/wpm_10202_31_13` SHA `c0f6574f34fd32b19de3b4bc4fd268c16191e52b4bf7c23956e85e748daea120`
明确写 `WARP:10204,2,6 / FREE:LV>29 / MONEY:-1`。原入口按等级≥30检查；服务器
check_passage/report_position 拒绝低等级常规入图，路由也不选该门。任务助手 near、
arrival 和自动任务初始入图是显式项目传送便利，允许绕过原入口，不能称原版规则。
审判接取保持原LV>0，不将入口限制错误移植为任务条件。

原长通道 `map/sainasu/dungeon/dan_1-02-04` 200×50，SHA
`e1941d76a9e3555839313ce320b340bd4544ea91c11345849ae6eb7f0d40a08b`；
`genout/dungeon00.create` SHA `1b3d189ea8ae5e42de4321efce19d3fb9517f0b25b6130ff0cb73761cd62514b`
保留(0,6)/(0,7)出口到10202(31,15)。按review-source导入原graphics/collision与原门，
8.0缺图只用真实2.5 fallback，不造入口。10204标dungeon，让手动步行也使用原遇敌。
encount208→groups322–326→enemies450–453，Lv20–30；原掉物1236，当前普通掉物仍未
启用（与现遇敌引擎一致），绝不掉仪玉。

自动任务在NPC间逐格AStar走原可行网格，每步复用server field_step；随机命中后暂停
任务，复用已有single_battle自动攻击及真实结算，获胜且存档成功后重derive任务继续。
不遇敌复用游戏助手通用角色开关。停止、手动移位、断线或组队停止所属battle runner，
未完战斗交回手动，不伪造胜利。服务器位置seq仅接受最近16条自己下发且发起设备/
连接匹配的回包，旧回包不倒退权威位置；实际手动位移仍停止。

成人独立checkpoint v1保存原pending troop、当前turn/state、战斗与遇敌RNG、原profile
及loot guard。只恢复单人450–453原敌群，不扩party/wood专用检查；当前completed_battles
已含id时不重复恢复奖励。真实文件测试覆盖周期与干净关机恢复，原交易token不恢复，
重derive不会重复发玉或仪之兜。SAVE_VERSION维持5，checkpoint版本独立。
